"""Phonologically-aware Needleman-Wunsch alignment.

Uniform Levenshtein treats /f/-for-/θ/ (mutually intelligible, ~90% of English
speakers understand) identically to /k/-for-/θ/ (unintelligible). That is
pedagogically wrong. We use three tiers:

  - exact match:            cost 0
  - same broad class:       cost 0.5  (e.g. both fricatives)
  - different class:        cost 1.0
  - insert / delete:        cost 1.0

This is cheap to implement, cheap to explain, and produces alignments that
match how a teacher would grade a learner.
"""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import List, Optional

# ---------------------------------------------------------------------------
# Phoneme classes. Each phoneme is assigned one broad articulatory class.
# Same-class substitutions cost less than different-class substitutions.
# ---------------------------------------------------------------------------

_CLASS_TABLE: dict[str, str] = {
    # Stops
    "p": "stop", "b": "stop", "t": "stop", "d": "stop", "k": "stop", "g": "stop",
    # Fricatives
    "f": "fricative", "v": "fricative", "θ": "fricative", "ð": "fricative",
    "s": "fricative", "z": "fricative", "ʃ": "fricative", "ʒ": "fricative",
    "h": "fricative",
    # Affricates (behave like fricatives for scoring purposes)
    "tʃ": "affricate", "dʒ": "affricate",
    # Nasals
    "m": "nasal", "n": "nasal", "ŋ": "nasal",
    # Approximants / liquids
    "l": "approximant", "r": "approximant", "ɹ": "approximant",
    "w": "approximant", "j": "approximant",
    # Front vowels
    "i": "vowel_front", "iː": "vowel_front", "ɪ": "vowel_front",
    "e": "vowel_front", "ɛ": "vowel_front", "æ": "vowel_front",
    # Central vowels
    "ə": "vowel_central", "ʌ": "vowel_central", "ɜ": "vowel_central",
    # Back vowels
    "u": "vowel_back", "uː": "vowel_back", "ʊ": "vowel_back",
    "o": "vowel_back", "ɔ": "vowel_back", "ɑ": "vowel_back", "ɒ": "vowel_back",
    # Diphthongs
    "aɪ": "diphthong", "aʊ": "diphthong", "eɪ": "diphthong",
    "oʊ": "diphthong", "ɔɪ": "diphthong",
}


def _phoneme_class(p: str) -> str:
    return _CLASS_TABLE.get(p, "other")


def _sub_cost(a: str, b: str) -> float:
    if a == b:
        return 0.0
    if _phoneme_class(a) == _phoneme_class(b):
        return 0.5
    return 1.0


_INDEL_COST = 1.0


class OpType(str, Enum):
    MATCH = "match"
    SUB = "substitution"
    DEL = "deletion"       # expected phoneme absent from what was produced
    INS = "insertion"      # extra phoneme produced that wasn't expected


@dataclass
class AlignedPair:
    op: OpType
    expected: Optional[str]   # None for INS
    actual: Optional[str]     # None for DEL
    expected_idx: Optional[int]  # position in expected sequence (for UI)


def align(expected: List[str], actual: List[str]) -> List[AlignedPair]:
    """Needleman-Wunsch alignment with phonologically-weighted costs.

    Returns a list of AlignedPair in expected order. Indels preserve
    expected_idx when relevant so the UI can highlight the right position.
    """
    n, m = len(expected), len(actual)

    # DP table. dp[i][j] = min cost to align expected[:i] to actual[:j].
    dp = [[0.0] * (m + 1) for _ in range(n + 1)]
    for i in range(1, n + 1):
        dp[i][0] = i * _INDEL_COST
    for j in range(1, m + 1):
        dp[0][j] = j * _INDEL_COST
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            sub = dp[i - 1][j - 1] + _sub_cost(expected[i - 1], actual[j - 1])
            dele = dp[i - 1][j] + _INDEL_COST
            ins = dp[i][j - 1] + _INDEL_COST
            dp[i][j] = min(sub, dele, ins)

    # Traceback.
    pairs: List[AlignedPair] = []
    i, j = n, m
    while i > 0 and j > 0:
        sub = dp[i - 1][j - 1] + _sub_cost(expected[i - 1], actual[j - 1])
        dele = dp[i - 1][j] + _INDEL_COST
        ins = dp[i][j - 1] + _INDEL_COST
        # Prefer match/sub when tied so we don't explode the alignment with indels.
        if dp[i][j] == sub:
            exp_p = expected[i - 1]
            act_p = actual[j - 1]
            op = OpType.MATCH if exp_p == act_p else OpType.SUB
            pairs.append(AlignedPair(op=op, expected=exp_p, actual=act_p, expected_idx=i - 1))
            i -= 1
            j -= 1
        elif dp[i][j] == dele:
            pairs.append(AlignedPair(op=OpType.DEL, expected=expected[i - 1], actual=None, expected_idx=i - 1))
            i -= 1
        else:
            pairs.append(AlignedPair(op=OpType.INS, expected=None, actual=actual[j - 1], expected_idx=None))
            j -= 1
    while i > 0:
        pairs.append(AlignedPair(op=OpType.DEL, expected=expected[i - 1], actual=None, expected_idx=i - 1))
        i -= 1
    while j > 0:
        pairs.append(AlignedPair(op=OpType.INS, expected=None, actual=actual[j - 1], expected_idx=None))
        j -= 1

    pairs.reverse()
    return pairs
