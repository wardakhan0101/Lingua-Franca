"""Confidence-based Goodness-of-Pronunciation scoring (Hu et al. 2015).

Classic GOP (Witt & Young 2000) requires CTC forward-backward over all paths
that emit a given phoneme at a given position — a full research project in
itself. We use the standard practical approximation:

  For each expected phoneme, look at the softmax posterior the model assigned
  to that phoneme's vocab id across the entire word's frame range. Take the
  MAX — i.e. "how confident was the model, at the best frame, that this
  phoneme was produced somewhere in this word?"

Why max-over-word instead of mean-over-slice:

  Our earlier approach divided the word's frames evenly across expected
  phonemes and took the mean posterior within each slice. That punished
  correct pronunciation on multi-syllable words because stressed syllables
  occupy uneven frame counts — the expected phoneme would end up outside
  its assigned slice and score near-zero. Max-over-word is robust to that
  because it only asks "was the phoneme present anywhere in the word?",
  which is what we actually care about for scoring.
"""
from __future__ import annotations

from typing import List, Optional

import numpy as np

from phoneme_aligner import AlignedPair, OpType


# Floor for a matched phoneme. Matched phonemes should feel correct in the UI
# (green), not mediocre (yellow). Raised from 60 → 80 based on empirical
# feedback that correct pronunciation was showing as "okay" scores.
_MATCH_FLOOR = 80.0

# Ceiling for a substitution — clearly below a match so the UI distinguishes
# correct vs incorrect at a glance.
_SUB_CEILING = 50.0

# Partial credit for a "deletion" pair. CTC greedy decoding often collapses
# consecutive same-phoneme frames or short unstressed phonemes into a single
# run, which the aligner then interprets as a missing phoneme. That isn't
# real mispronunciation — the phoneme may still be present acoustically.
# 50 is a middle ground: not a free pass (distinguishable from matches), but
# not punitive zero (which destroyed word scores on multi-syllable words).
_DEL_FLOOR = 50.0


def score_aligned_pairs(
    pairs: List[AlignedPair],
    word_frame_span: tuple[int, int],
    posteriors: np.ndarray,
    phoneme_to_ids: dict[str, List[int]],
) -> List[Optional[int]]:
    """Score each expected phoneme 0-100.

    Args:
      pairs: alignment output from phoneme_aligner.
      word_frame_span: (start_frame, end_frame) for the entire word. Every
        expected phoneme is scored using the posterior within this range.
      posteriors: (num_frames, vocab_size) softmax array over the whole audio.
      phoneme_to_ids: canonicalized-phoneme → list of vocab ids (multiple
        vocab tokens can canonicalize to the same phoneme after stripping
        stress/length marks).

    Returns one score per EXPECTED phoneme position (in order).
    """
    sf, ef = word_frame_span
    sf = max(0, sf)
    ef = min(posteriors.shape[0], ef)
    if ef <= sf:
        # Zero-length word — can't score.
        return [None for p in pairs if p.expected_idx is not None]

    word_posteriors = posteriors[sf:ef]  # (T_word, V)

    # Group pairs by expected_idx so output order = expected order.
    by_idx: dict[int, AlignedPair] = {}
    for p in pairs:
        if p.expected_idx is not None:
            by_idx[p.expected_idx] = p

    max_expected = max(by_idx.keys()) if by_idx else -1
    scores: List[Optional[int]] = []

    for idx in range(max_expected + 1):
        pair = by_idx.get(idx)
        if pair is None or pair.expected is None:
            scores.append(None)
            continue

        expected_phoneme = pair.expected
        op = pair.op

        # Deletion — CTC never decoded this phoneme. Give partial credit
        # because short/unstressed phonemes are routinely collapsed by CTC
        # greedy even when they're acoustically present.
        if op == OpType.DEL:
            scores.append(int(_DEL_FLOOR))
            continue

        ids = phoneme_to_ids.get(expected_phoneme, [])
        if not ids:
            # Phoneme not in the Wav2Vec2 vocab at all (canonicalizer edge
            # case). Fall back to alignment verdict only.
            scores.append(int(_MATCH_FLOOR) if op == OpType.MATCH else int(_SUB_CEILING))
            continue

        # Max posterior across the word for this phoneme's id(s).
        # Summing across equivalent ids first — some phonemes have multiple
        # vocab entries after canonicalization.
        phoneme_mass = word_posteriors[:, ids].sum(axis=1)
        peak = float(phoneme_mass.max())
        raw = peak * 100.0  # 0–100

        if op == OpType.MATCH:
            # Floor because the alignment agreed the phoneme was produced —
            # even if the acoustic confidence is middling we shouldn't punish.
            score = max(_MATCH_FLOOR, raw)
        else:  # SUB
            # Substitution — the phoneme was replaced. Cap well below the
            # match floor so the UI shows a clear gap.
            score = min(_SUB_CEILING, raw)

        scores.append(int(round(max(0.0, min(100.0, score)))))

    return scores


def word_score(phoneme_scores: List[Optional[int]]) -> Optional[int]:
    """Aggregate per-phoneme scores into a word-level score.
    None entries are excluded (unknown phonemes). If everything is None, return None.
    """
    valid = [s for s in phoneme_scores if s is not None]
    if not valid:
        return None
    return int(round(sum(valid) / len(valid)))


def overall_score(word_scores: List[Optional[int]]) -> int:
    """Aggregate word scores into an overall session score (0-100).
    None words are excluded (skipped / proper nouns / too short).
    If all words were skipped, fall back to 0 so the UI doesn't show a lie.
    """
    valid = [s for s in word_scores if s is not None]
    if not valid:
        return 0
    return int(round(sum(valid) / len(valid)))
