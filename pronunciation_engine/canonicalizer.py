"""Normalize eSpeak IPA phoneme strings.

Both sides of the alignment must be canonicalized identically, or the
comparison is meaningless. This is the single most important correctness
surface in the engine — most demo-day bugs live here.

Transformations:
  - strip length mark  ː
  - strip stress marks ˈ ˌ
  - strip tie bar      ͡
  - strip whitespace and separators
  - collapse affricates so Wav2Vec2's "tʃ" matches phonemizer's "tʃ"
  - map a handful of equivalents the two tools disagree on
"""
from typing import List

# Characters to strip unconditionally from any phoneme token.
_STRIP_CHARS = set("ːˈˌ͡‿ ˑ")

# Phoneme-level equivalents where phonemizer / Wav2Vec2 disagree on surface form.
# Keys are written in whatever variant shows up; values are the canonical form.
_EQUIVALENTS = {
    "ɝ": "ɜɹ",   # r-colored schwa (US) → schwa + rhotic
    "ɚ": "əɹ",
    "ɹ": "ɹ",
    "r": "ɹ",    # Some phonemizer variants emit plain r
    "ɫ": "l",    # dark l → l
    "ɾ": "t",    # flap → t (close enough for L2 assessment)
    "ʔ": "",     # glottal stop — drop (both tools emit it inconsistently)
    "ɐ": "ʌ",
    "ɒ": "ɑ",
    "ɔ": "ɔ",
}


def canonicalize_phoneme(p: str) -> str:
    """Canonicalize a single phoneme token."""
    out = "".join(ch for ch in p if ch not in _STRIP_CHARS)
    out = _EQUIVALENTS.get(out, out)
    return out


def canonicalize_sequence(phonemes: List[str]) -> List[str]:
    """Canonicalize a list of phonemes, dropping empties."""
    result = []
    for p in phonemes:
        c = canonicalize_phoneme(p)
        if c:
            result.append(c)
    return result


def split_espeak_string(s: str) -> List[str]:
    """Split an eSpeak phoneme string into individual phoneme tokens.

    eSpeak separates phonemes with spaces or underscores depending on flags.
    We handle both and also split concatenated IPA characters character-by-character
    only when no separator is present (fallback).
    """
    s = s.strip()
    if not s:
        return []
    # Prefer explicit separators
    for sep in (" ", "_"):
        if sep in s:
            return [tok for tok in s.split(sep) if tok]
    # Fallback: split per character (works for most single-char IPA symbols)
    # but keep common digraphs together
    digraphs = {"tʃ", "dʒ", "aɪ", "aʊ", "eɪ", "oʊ", "ɔɪ", "ɪə", "ʊə", "eə"}
    tokens = []
    i = 0
    while i < len(s):
        # Try digraph first
        if i + 1 < len(s) and s[i : i + 2] in digraphs:
            tokens.append(s[i : i + 2])
            i += 2
        else:
            tokens.append(s[i])
            i += 1
    return tokens
