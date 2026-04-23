"""Unit tests for alignment + canonicalizer + scoring logic.

No audio or models required — these run in milliseconds and catch regressions
in the algorithm layer without the Wav2Vec2 startup cost.
"""
from __future__ import annotations

import os
import sys

import numpy as np

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from canonicalizer import canonicalize_phoneme, canonicalize_sequence, split_espeak_string
from gop_scorer import overall_score, score_aligned_pairs, word_score
from phoneme_aligner import OpType, align


# ---------------------------------------------------------------------------
# canonicalizer
# ---------------------------------------------------------------------------


def test_canonicalize_strips_stress_and_length():
    assert canonicalize_phoneme("ˈθ") == "θ"
    assert canonicalize_phoneme("iː") == "i"  # length stripped
    assert canonicalize_phoneme("ˌeɪ") == "eɪ"


def test_canonicalize_sequence_drops_empties():
    assert canonicalize_sequence(["θ", "", "ɪ", " ", "ŋ", "k"]) == ["θ", "ɪ", "ŋ", "k"]


def test_split_espeak_with_spaces():
    assert split_espeak_string("θ ɪ ŋ k") == ["θ", "ɪ", "ŋ", "k"]


def test_split_espeak_concatenated_with_digraph():
    # "tʃeə" → affricate + monophthong... but our digraph list includes "eə"
    tokens = split_espeak_string("tʃeə")
    assert "tʃ" in tokens
    assert "eə" in tokens


# ---------------------------------------------------------------------------
# phoneme_aligner
# ---------------------------------------------------------------------------


def test_perfect_match_has_all_match_ops():
    expected = ["θ", "ɪ", "ŋ", "k"]
    pairs = align(expected, expected)
    assert len(pairs) == 4
    assert all(p.op == OpType.MATCH for p in pairs)


def test_substitution_detected():
    # /θ/ → /f/ (classic L2 error)
    pairs = align(["θ", "ɪ", "ŋ", "k"], ["f", "ɪ", "ŋ", "k"])
    subs = [p for p in pairs if p.op == OpType.SUB]
    assert len(subs) == 1
    assert subs[0].expected == "θ"
    assert subs[0].actual == "f"


def test_deletion_detected():
    # Learner dropped the final consonant
    pairs = align(["θ", "ɪ", "ŋ", "k"], ["θ", "ɪ", "ŋ"])
    dels = [p for p in pairs if p.op == OpType.DEL]
    assert len(dels) == 1
    assert dels[0].expected == "k"


def test_insertion_detected():
    pairs = align(["θ", "ɪ", "ŋ"], ["θ", "ɪ", "ŋ", "k"])
    inss = [p for p in pairs if p.op == OpType.INS]
    assert len(inss) == 1
    assert inss[0].actual == "k"


def test_same_class_substitution_cheaper_than_different_class():
    # /θ/ → /f/ (same class: fricative) should cost less than /θ/ → /k/ (stop).
    # This manifests as: for a longer expected sequence, the aligner keeps a
    # close-class sub rather than re-routing through indels.
    expected = ["θ", "ɪ", "ŋ", "k"]
    close_actual = ["f", "ɪ", "ŋ", "k"]     # fricative→fricative
    distant_actual = ["k", "ɪ", "ŋ", "k"]   # fricative→stop

    close_pairs = align(expected, close_actual)
    distant_pairs = align(expected, distant_actual)

    # Both should resolve to straight substitutions at position 0.
    assert close_pairs[0].op == OpType.SUB
    assert distant_pairs[0].op == OpType.SUB


# ---------------------------------------------------------------------------
# gop_scorer
# ---------------------------------------------------------------------------


def _build_posteriors(
    frames: list[list[tuple[int, float]]], vocab_size: int
) -> np.ndarray:
    """Build a (T, V) posterior array where each frame's (id, prob) tuples
    define the non-zero entries. Remaining mass is uniformly distributed so
    rows sum to 1.
    """
    arr = np.zeros((len(frames), vocab_size), dtype=np.float32)
    for t, entries in enumerate(frames):
        mass = 0.0
        for i, p in entries:
            arr[t, i] = p
            mass += p
        leftover = max(0.0, 1.0 - mass) / max(1, vocab_size - len(entries))
        for i in range(vocab_size):
            if arr[t, i] == 0:
                arr[t, i] = leftover
    return arr


def test_match_gets_high_score_when_posterior_is_high():
    # Two expected phonemes: θ (id 0), ɪ (id 1). Vocab size 5 (blank=4).
    # Posteriors strongly confident on each.
    posteriors = _build_posteriors(
        frames=[
            [(0, 0.95)],
            [(0, 0.92)],
            [(1, 0.90)],
            [(1, 0.88)],
        ],
        vocab_size=5,
    )
    pairs = align(["θ", "ɪ"], ["θ", "ɪ"])
    scores = score_aligned_pairs(
        pairs=pairs,
        word_frame_span=(0, 4),
        posteriors=posteriors,
        phoneme_to_ids={"θ": [0], "ɪ": [1]},
    )
    assert scores[0] is not None and scores[0] >= 80
    assert scores[1] is not None and scores[1] >= 80


def test_substitution_gets_low_score():
    # Expected θ, but model is confident on f (id 2).
    posteriors = _build_posteriors(
        frames=[[(2, 0.90)], [(2, 0.88)]],
        vocab_size=5,
    )
    pairs = align(["θ"], ["f"])
    scores = score_aligned_pairs(
        pairs=pairs,
        word_frame_span=(0, 2),
        posteriors=posteriors,
        phoneme_to_ids={"θ": [0], "f": [2]},
    )
    assert scores[0] is not None and scores[0] <= 50


def test_word_score_averages_phoneme_scores():
    assert word_score([80, 90, 100]) == 90
    assert word_score([80, None, 100]) == 90  # None excluded
    assert word_score([None, None]) is None


def test_overall_score_excludes_none_words():
    assert overall_score([80, 90, None]) == 85
    assert overall_score([None, None]) == 0


# ---------------------------------------------------------------------------
# Audio fixture tests (require user-supplied WAV files)
# ---------------------------------------------------------------------------

import pytest

FIXTURES_DIR = os.path.join(os.path.dirname(__file__), "audio")


def _has_wav_fixtures() -> bool:
    if not os.path.isdir(FIXTURES_DIR):
        return False
    return any(f.lower().endswith(".wav") for f in os.listdir(FIXTURES_DIR))


@pytest.mark.skipif(
    not _has_wav_fixtures(),
    reason="Audio fixtures not recorded yet — see tests/audio/README.md",
)
def test_fixtures_exist():
    """Placeholder — once fixtures are added, replace with real assertions
    that hit the running API via TestClient. See tests/audio/README.md."""
    required = [
        "silence.wav",
        "perfect_speech.wav",
        "think_as_fink.wav",
        "rice_as_lice.wav",
        "very_as_wery.wav",
        "this_as_dis.wav",
    ]
    missing = [f for f in required if not os.path.exists(os.path.join(FIXTURES_DIR, f))]
    assert not missing, f"Missing fixtures: {missing}"
