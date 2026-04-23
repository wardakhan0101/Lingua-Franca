"""Learner-facing labels and articulation hints for the most common
L2-English phonemes. Returned with the API response so the Flutter client
doesn't need to ship an IPA → English table.
"""
from typing import Dict, Optional

# Human-readable label shown alongside the IPA symbol in the UI.
IPA_LABELS: Dict[str, str] = {
    "θ": "th (as in think)",
    "ð": "th (as in this)",
    "ʃ": "sh (as in ship)",
    "ʒ": "s (as in measure)",
    "tʃ": "ch (as in chair)",
    "dʒ": "j (as in jump)",
    "ŋ": "ng (as in sing)",
    "r": "r",
    "ɹ": "r",
    "l": "l",
    "v": "v",
    "w": "w",
    "f": "f",
    "b": "b",
    "p": "p",
    "d": "d",
    "t": "t",
    "k": "k",
    "g": "g",
    "s": "s",
    "z": "z",
    "m": "m",
    "n": "n",
    "h": "h",
    "j": "y (as in yes)",
    "iː": "ee (as in see)",
    "i": "ee (short)",
    "ɪ": "i (as in sit)",
    "e": "e (as in bed)",
    "ɛ": "e (as in bed)",
    "æ": "a (as in cat)",
    "ɑ": "a (as in father)",
    "ɒ": "o (as in hot)",
    "ɔ": "aw (as in thought)",
    "ʊ": "u (as in put)",
    "uː": "oo (as in boot)",
    "u": "oo (short)",
    "ʌ": "u (as in cup)",
    "ə": "uh (schwa)",
    "ɜ": "er (as in bird)",
    "aɪ": "eye",
    "aʊ": "ow (as in now)",
    "eɪ": "ay (as in say)",
    "oʊ": "oh",
    "ɔɪ": "oy (as in boy)",
}

# Articulation hints for the phonemes that L2 speakers most commonly mispronounce.
# Short enough to fit on a card without truncation.
HINTS: Dict[str, str] = {
    "θ": "Place your tongue between your teeth and blow air gently.",
    "ð": "Tongue between teeth, voice on — a soft buzz.",
    "r": "Curl your tongue back without touching the roof of your mouth.",
    "ɹ": "Curl your tongue back without touching the roof of your mouth.",
    "l": "Touch the tip of your tongue to the ridge behind your upper teeth.",
    "v": "Upper teeth touch your lower lip — voice on.",
    "w": "Round your lips, no teeth contact — like saying 'oo' into a vowel.",
    "f": "Upper teeth touch lower lip — push air, no voice.",
    "ʃ": "Round your lips slightly and hiss softly.",
    "ʒ": "Same shape as 'sh' but with voice — like the middle of 'measure'.",
    "tʃ": "Start with 't', then release into 'sh'.",
    "dʒ": "Start with 'd', then release into the 'zh' sound.",
    "ŋ": "Back of tongue touches the soft palate — sound through nose.",
    "z": "Same as 's' but with voice — a buzz.",
    "æ": "Open your mouth wide — jaw low, tongue forward.",
    "ɪ": "Short, relaxed — don't stretch it into 'ee'.",
    "ə": "Neutral, unstressed — mouth relaxed.",
}


def label_for(p: str) -> str:
    """Return human-readable label or fall back to the IPA itself."""
    return IPA_LABELS.get(p, p)


def hint_for(expected: str, actual: Optional[str]) -> str:
    """Return articulation hint for the expected phoneme; falls back to generic."""
    hint = HINTS.get(expected)
    if hint:
        return hint
    return f"Focus on producing the {label_for(expected)} sound clearly."
