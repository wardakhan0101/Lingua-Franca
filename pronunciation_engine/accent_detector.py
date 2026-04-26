"""Heuristic accent classifier over already-extracted phoneme stats.

The pronunciation engine produces, per session:
  - `phoneme_stats` — for every IPA phoneme the user was *expected* to
    produce, how many times the recognizer agreed and what it
    substituted in when it didn't.
  - `per_word`     — for every analyzable word, the expected and actual
    phoneme sequences side-by-side.

That data is already strongly correlated with the speaker's English
accent. Rather than ship a second neural model and pay the inference
cost, this module votes across a small set of well-documented L2
phonetic markers and returns one of three labels:

    american  | british  | pakistani  | None  (when evidence is too thin)

These three classes match the existing TTS dropdown buckets, which keeps
the rest of the app's accent vocabulary consistent.

Important interaction with `canonicalizer.py`:
  - /r/ and /ɹ/ both canonicalize to /ɹ/, so rhoticity always shows up
    keyed under "ɹ".
  - /ɝ/ (rhotic schwa) expands to /ɜɹ/ and /ɚ/ to /əɹ/, so an /ɹ/ is
    visible at the position where it would be pronounced.
  - /ɾ/ (alveolar flap) is folded into /t/ — so American flap-T is NOT
    detectable from this data and is intentionally not used as a marker.
  - Length marks (ː) are stripped — the British BATH /ɑː/ vs American
    /ɑ/ length contrast is invisible here, also intentionally skipped.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple


# Don't commit to a label until we've heard enough words to be on solid
# ground — a 3-word session can easily look "Pakistani" by accident.
MIN_SCORED_WORDS = 8

# Sum of weighted votes required before we'll commit to ANY label. Below
# this we return None and the UI hides the card.
MIN_TOTAL_VOTES = 4.0

# Winner has to clear this share of the total vote, or the result is too
# close to call (3-class chance is ~33%, so 0.45 leaves margin).
MIN_WINNING_SHARE = 0.45

# Phoneme groups — the canonicalizer mostly normalizes to a single form,
# but we still accept a few near-equivalents in case upstream tools emit
# a dental or retroflex diacritic that slips through.
_T_LIKE = {"t", "t̪", "ʈ"}        # alveolar / dental / retroflex stop
_D_LIKE = {"d", "d̪", "ɖ"}
_R_LIKE = {"ɹ", "r", "ɻ"}


def detect_accent(
    per_word: List[Dict[str, Any]],
    phoneme_stats: Dict[str, Dict[str, Any]],
) -> Dict[str, Any]:
    """Return {label, confidence, evidence}.

    `label` is one of {"american", "british", "pakistani", None}. None
    when the audio was too short, evidence too thin, or the vote was too
    close to call. `confidence` is the winner's share of total weighted
    votes (0.0–1.0). `evidence` is up to three short human-readable
    bullets describing the strongest markers that fired — these are
    rendered as-is on the report screen.
    """
    scored_words = [w for w in per_word if w.get("score") is not None]
    if len(scored_words) < MIN_SCORED_WORDS:
        return {"label": None, "confidence": 0.0, "evidence": []}

    votes: Dict[str, float] = {"american": 0.0, "british": 0.0, "pakistani": 0.0}
    # (text, weight) so we can sort and keep only the strongest evidence.
    evidence: List[Tuple[str, float]] = []

    # ---- Pakistani markers --------------------------------------------------

    # /θ/ → /t/ ("think" → "tink"). A near-universal South Asian English
    # marker. Weighted heavily because it almost never fires for L1
    # American/British speakers.
    theta = phoneme_stats.get("θ", {}) or {}
    theta_subs = theta.get("substitutions", {}) or {}
    theta_to_t = sum(c for sub, c in theta_subs.items() if sub in _T_LIKE)
    theta_total = int(theta.get("expected", 0) or 0)
    if theta_total >= 2 and theta_to_t >= 2:
        weight = 2.0 * theta_to_t
        votes["pakistani"] += weight
        evidence.append((f"/θ/→/t/ in {theta_to_t}/{theta_total} words", weight))

    # /ð/ → /d/ ("this" → "dis"). Same family of substitution.
    eth = phoneme_stats.get("ð", {}) or {}
    eth_subs = eth.get("substitutions", {}) or {}
    eth_to_d = sum(c for sub, c in eth_subs.items() if sub in _D_LIKE)
    eth_total = int(eth.get("expected", 0) or 0)
    if eth_total >= 2 and eth_to_d >= 2:
        weight = 2.0 * eth_to_d
        votes["pakistani"] += weight
        evidence.append((f"/ð/→/d/ in {eth_to_d}/{eth_total} words", weight))

    # /v/ ↔ /w/ merger (Pakistani/Indian). Counted in either direction.
    v_stats = phoneme_stats.get("v", {}) or {}
    w_stats = phoneme_stats.get("w", {}) or {}
    v_to_w = int((v_stats.get("substitutions", {}) or {}).get("w", 0) or 0)
    w_to_v = int((w_stats.get("substitutions", {}) or {}).get("v", 0) or 0)
    vw = v_to_w + w_to_v
    if vw >= 2:
        weight = 1.5 * vw
        votes["pakistani"] += weight
        plural = "s" if vw > 1 else ""
        evidence.append((f"/v/↔/w/ confusion in {vw} place{plural}", weight))

    # ---- Rhoticity (American vs British) -----------------------------------
    #
    # For every scored word whose expected phonemes contain an /ɹ/ in the
    # last two positions (covers word-final "car" and pre-consonantal
    # "park"), check whether the recognizer also heard an /ɹ/ anywhere
    # in the actual phoneme set. Kept-r → +american; dropped-r →
    # +british. Only one of the two can win per session.
    coda_words_total = 0
    coda_r_kept = 0
    coda_r_dropped = 0
    for w in scored_words:
        expected = w.get("expected_phonemes") or []
        if not expected:
            continue
        coda = expected[-2:] if len(expected) >= 2 else expected
        if not any(p in _R_LIKE for p in coda):
            continue
        coda_words_total += 1
        actual = w.get("actual_phonemes") or []
        if any(p in _R_LIKE for p in actual):
            coda_r_kept += 1
        else:
            coda_r_dropped += 1

    if coda_words_total >= 3:
        if coda_r_kept >= coda_r_dropped:
            weight = 1.5 * coda_r_kept
            if weight > 0:
                votes["american"] += weight
                evidence.append(
                    (f"kept /r/ at end of {coda_r_kept}/{coda_words_total} words", weight)
                )
        else:
            weight = 1.5 * coda_r_dropped
            votes["british"] += weight
            evidence.append(
                (f"dropped /r/ at end of {coda_r_dropped}/{coda_words_total} words", weight)
            )

    # ---- Decision -----------------------------------------------------------

    total_votes = sum(votes.values())
    if total_votes < MIN_TOTAL_VOTES:
        return {"label": None, "confidence": 0.0, "evidence": []}

    label = max(votes, key=lambda k: votes[k])
    share = votes[label] / total_votes
    if share < MIN_WINNING_SHARE:
        return {"label": None, "confidence": 0.0, "evidence": []}

    evidence.sort(key=lambda e: -e[1])
    return {
        "label": label,
        "confidence": round(share, 2),
        "evidence": [text for text, _ in evidence[:3]],
    }
