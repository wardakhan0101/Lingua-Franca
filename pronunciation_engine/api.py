"""Pronunciation Analysis Engine — FastAPI entry point.

Accepts audio + transcript + Whisper word timestamps, compares the phonemes
the learner produced (Wav2Vec2 acoustic recognition) against the phonemes
they were expected to produce (phonemizer/espeak-ng), and returns per-word
and overall pronunciation scores with per-phoneme breakdowns.
"""
from __future__ import annotations

import json
import os
import re
import tempfile
from collections import defaultdict
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from phonemizer import phonemize
from phonemizer.backend import EspeakBackend

from canonicalizer import canonicalize_sequence, split_espeak_string
from gop_scorer import overall_score, score_aligned_pairs, word_score
from phoneme_aligner import align
from phoneme_hints import hint_for, label_for
from phoneme_recognizer import PhonemeRecognizer

app = FastAPI(title="Pronunciation Analysis Engine", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Fail loud at startup if espeak-ng is missing — much better than failing at
# request time with a cryptic error.
try:
    _startup_probe = phonemize("test", language="en-us", backend="espeak", strip=True)
    if not _startup_probe:
        raise RuntimeError("phonemizer returned empty output for probe")
    print(f"[pronunciation_engine] espeak-ng OK (probe='{_startup_probe}')")
except Exception as exc:
    raise RuntimeError(
        "espeak-ng is not installed or not reachable by phonemizer. "
        "Install with: `brew install espeak-ng` (macOS) or "
        "`apt install espeak-ng` (Debian/Ubuntu)."
    ) from exc

# Reuse one backend instance across requests (espeak spin-up is ~300ms).
_espeak = EspeakBackend("en-us", preserve_punctuation=False, with_stress=False)

print("[pronunciation_engine] Loading phoneme recognizer…")
recognizer = PhonemeRecognizer()

# Cache: canonicalized-phoneme -> list of vocab ids that map to it. Multiple
# raw vocab tokens can canonicalize to the same phoneme (stress variants).
_phoneme_to_ids: Dict[str, List[int]] = defaultdict(list)
for idx, phoneme in enumerate(recognizer.id_to_phoneme):
    if phoneme:
        _phoneme_to_ids[phoneme].append(idx)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# A word is considered too short to score reliably if its audio span is under
# 300ms — Wav2Vec2 confidence is noisy on very short clips.
MIN_WORD_DURATION = 0.3


def _normalize_word(raw: str) -> str:
    """Lowercase + strip punctuation — same tokenization on both sides."""
    return re.sub(r"[^\w']", "", raw.lower()).strip()


def _phonemize_word(word: str) -> tuple[List[str], bool]:
    """Return (canonicalized_phonemes, is_oov).

    `is_oov` is True when phonemizer's output looks like a G2P fallback —
    i.e., the word wasn't in espeak's dictionary (proper nouns like "Ayesha").
    We approximate this by checking for the language-switch marker or an
    abnormally long phoneme string relative to the input.
    """
    try:
        raw = phonemize(
            word,
            language="en-us",
            backend="espeak",
            strip=True,
            preserve_punctuation=False,
            with_stress=False,
            language_switch="remove-flags",
        )
    except Exception:
        return [], True

    raw = raw.strip()
    if not raw:
        return [], True

    # espeak-ng marks language-switches with "(en-..)" or similar markers.
    # After `language_switch="remove-flags"` those markers are stripped, but
    # leftover parentheses indicate the word was OOV.
    is_oov = "(" in raw or ")" in raw or not re.search(r"[a-zA-Zɑ-ʯæðŋθʃʒʊəɔɪ]", raw)

    phonemes = canonicalize_sequence(split_espeak_string(raw))
    return phonemes, is_oov


def _build_issue(
    expected: str,
    actual: Optional[str],
    position: int,
    op: str,
) -> Dict[str, Any]:
    return {
        "type": op,
        "expected": expected,
        "actual": actual,
        "position": position,
        "expected_ipa_label": label_for(expected),
        "hint": hint_for(expected, actual),
    }


# ---------------------------------------------------------------------------
# Request handler
# ---------------------------------------------------------------------------


@app.post("/analyze")
async def analyze(
    file: UploadFile = File(...),
    transcript: str = Form(...),
    whisper_words: str = Form(...),
):
    """Analyze pronunciation of the given audio against the transcript.

    `whisper_words` is a JSON string: [{"word": "...", "start": float, "end": float}, ...]
    It comes from the fluency engine's Whisper output — we do not re-transcribe.
    """
    try:
        words_list = json.loads(whisper_words)
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail=f"whisper_words is not valid JSON: {exc}")

    if not isinstance(words_list, list):
        raise HTTPException(status_code=400, detail="whisper_words must be a JSON array")

    suffix = os.path.splitext(file.filename or "audio.wav")[1] or ".wav"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(await file.read())
        audio_path = tmp.name

    try:
        # Whole-audio inference.
        inference = recognizer.infer(audio_path)

        per_word: List[Dict[str, Any]] = []
        phoneme_stats: Dict[str, Dict[str, Any]] = defaultdict(
            lambda: {"expected": 0, "correct": 0, "substitutions": defaultdict(int)}
        )

        for w in words_list:
            raw_word = str(w.get("word", ""))
            start = float(w.get("start", 0.0))
            end = float(w.get("end", 0.0))
            clean = _normalize_word(raw_word)

            if not clean:
                continue

            # Minimum length guard — too-short audio is unreliable.
            if end - start < MIN_WORD_DURATION:
                per_word.append({
                    "word": clean,
                    "score": None,
                    "start": start,
                    "end": end,
                    "expected_phonemes": [],
                    "actual_phonemes": [],
                    "phoneme_scores": [],
                    "issues": [],
                    "skipped_reason": "too_short",
                })
                continue

            expected_phonemes, is_oov = _phonemize_word(clean)

            if is_oov or not expected_phonemes:
                per_word.append({
                    "word": clean,
                    "score": None,
                    "start": start,
                    "end": end,
                    "expected_phonemes": expected_phonemes,
                    "actual_phonemes": [],
                    "phoneme_scores": [],
                    "issues": [],
                    "skipped_reason": "unknown_word",
                })
                continue

            # Slice CTC frames for this word with ±2-frame pad (~40ms).
            _, _, sf, ef = recognizer.slice_frames(inference, start, end, pad_frames=2)
            actual_phonemes = recognizer.greedy_in_range(inference, sf, ef)

            # Alignment drives scoring and issue detection.
            pairs = align(expected_phonemes, actual_phonemes)

            # Score each expected phoneme using the max posterior across the
            # entire word's frame range — robust to stressed-syllable timing
            # drift that broke the old equal-split approach.
            phoneme_scores = score_aligned_pairs(
                pairs=pairs,
                word_frame_span=(sf, ef),
                posteriors=inference.posteriors,
                phoneme_to_ids=_phoneme_to_ids,
            )

            # Build per-word issues (only substitutions + deletions — insertions
            # are less pedagogically useful and clutter the UI).
            issues: List[Dict[str, Any]] = []
            for pair in pairs:
                if pair.op == "substitution" and pair.expected and pair.expected_idx is not None:
                    issues.append(_build_issue(pair.expected, pair.actual, pair.expected_idx, "substitution"))
                elif pair.op == "deletion" and pair.expected and pair.expected_idx is not None:
                    issues.append(_build_issue(pair.expected, None, pair.expected_idx, "deletion"))

            # Update per-phoneme stats.
            #
            # A phoneme is counted as "correct" when either:
            #   (a) the aligner matched it, OR
            #   (b) the acoustic score ≥ 70 — i.e. the phoneme's softmax
            #       posterior peaked high somewhere in the word range.
            # (b) catches the common case where Wav2Vec2's CTC greedy
            # decoder collapses consecutive same-phoneme frames, which the
            # aligner then calls a DEL even though the phoneme was clearly
            # pronounced. Without this, the UI's phoneme-accuracy bars sit
            # at 0% for real sessions.
            for idx, expected_p in enumerate(expected_phonemes):
                phoneme_stats[expected_p]["expected"] += 1

                op_for_idx = None
                sub_actual: Optional[str] = None
                for pair in pairs:
                    if pair.expected_idx == idx:
                        op_for_idx = pair.op
                        if pair.op == "substitution" and pair.actual:
                            sub_actual = pair.actual
                        break

                score_for_idx = (
                    phoneme_scores[idx]
                    if idx < len(phoneme_scores) and phoneme_scores[idx] is not None
                    else None
                )
                acoustic_ok = score_for_idx is not None and score_for_idx >= 70

                if op_for_idx == "match" or acoustic_ok:
                    phoneme_stats[expected_p]["correct"] += 1
                elif sub_actual:
                    phoneme_stats[expected_p]["substitutions"][sub_actual] += 1

            per_word.append({
                "word": clean,
                "score": word_score(phoneme_scores),
                "start": start,
                "end": end,
                "expected_phonemes": expected_phonemes,
                "actual_phonemes": actual_phonemes,
                "phoneme_scores": [s if s is not None else 0 for s in phoneme_scores],
                "issues": issues,
            })

        # Silence / near-silence detection — if the greedy decode is almost
        # entirely blanks across the whole audio, override the overall score
        # to something low. Without this the engine happily hands back high
        # scores for silent audio (since there's nothing to misalign against).
        non_blank_frames = int((inference.greedy_ids != inference.blank_id).sum())
        ratio_non_blank = non_blank_frames / max(1, inference.num_frames)

        overall = overall_score([w["score"] for w in per_word])
        if ratio_non_blank < 0.05:
            overall = min(overall, 15)

        # Convert defaultdicts to regular dicts for JSON.
        phoneme_stats_out = {
            p: {
                "expected": v["expected"],
                "correct": v["correct"],
                "substitutions": dict(v["substitutions"]),
            }
            for p, v in phoneme_stats.items()
        }

        return {
            "overall_score": overall,
            "per_word": per_word,
            "phoneme_stats": phoneme_stats_out,
        }

    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Analysis failed: {exc}")
    finally:
        try:
            os.remove(audio_path)
        except OSError:
            pass


@app.get("/health")
async def health():
    return {"status": "ok", "model": "wav2vec2-lv-60-espeak-cv-ft + espeak-ng"}
