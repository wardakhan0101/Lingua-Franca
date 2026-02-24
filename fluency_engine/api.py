from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import whisper
import spacy
import tempfile
import os
import re
from typing import List, Dict, Any, Set

app = FastAPI(title="Fluency Analysis Engine", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Load models once at startup
print("Loading Whisper model...")
model = whisper.load_model("base")
print("Whisper model loaded.")

print("Loading spaCy model...")
nlp = spacy.load("en_core_web_sm")
print("spaCy model loaded.")

# ---------------------------------------------------------------------------
# Filler Word Definitions
# ---------------------------------------------------------------------------

# Hard fillers: phonetic hesitation sounds — NEVER a content word. Always flagged.
HARD_FILLERS: Set[str] = {'um', 'uh', 'hmm', 'hm', 'er', 'ah', 'eh'}

# Soft fillers: real words with dual roles (content vs. discourse marker).
# Context is needed to decide. spaCy + position heuristics handle this.
SOFT_FILLERS: Set[str] = {
    'so', 'like', 'basically', 'actually', 'literally',
    'right', 'okay', 'well', 'yeah', 'you know', 'i mean',
    'sort', 'kind', 'mean'
}

# spaCy dependency labels that indicate a word is a DISCOURSE MARKER (filler role)
FILLER_DEPS = {'cc', 'mark', 'intj', 'discourse', 'advmod'}

# spaCy POS tags that indicate the word is functioning as content
CONTENT_POS = {'VERB', 'ADJ', 'NOUN', 'PROPN', 'NUM'}

# spaCy head POS: if a soft filler modifies an ADJ or ADV, it's an intensifier (not filler)
# e.g. "so tired" → "so" advmod → head "tired" is ADJ → content use
INTENSIFIER_HEAD_POS = {'ADJ', 'ADV'}


def is_soft_filler_contextual(token) -> bool:
    """
    Use spaCy dependency parse to decide if a soft filler word is
    acting as a filler (discourse marker / sentence starter) or as
    a real content word.

    Returns True = IS a filler, False = content word, skip it.
    """
    dep = token.dep_
    pos = token.pos_
    head_pos = token.head.pos_

    # "so tired", "so quickly" — "so" is an intensifier modifying ADJ/ADV → NOT filler
    if dep == 'advmod' and head_pos in INTENSIFIER_HEAD_POS:
        return False

    # "I like pizza" — "like" is a verb → NOT filler
    if pos == 'VERB':
        return False

    # "That's right" where right is adjective predicate → NOT filler
    if dep in {'acomp', 'attr'} and pos == 'ADJ':
        return False

    # "Turn right" — direction adverb → NOT filler
    if dep == 'advmod' and token.text.lower() == 'right' and head_pos == 'VERB':
        return False

    # "She did well" — manner adverb → NOT filler
    if dep == 'advmod' and token.text.lower() == 'well' and head_pos == 'VERB':
        return False

    # Discourse markers, conjunctions, interjections → FILLER
    if dep in FILLER_DEPS:
        return True

    # Sentence-initial position (ROOT or first token in doc) → FILLER
    if dep == 'ROOT' and pos not in CONTENT_POS:
        return True

    # Default: assume content word (conservative — avoid false positives)
    return False


def is_soft_filler_position(word_data: Dict, all_words: List[Dict]) -> bool:
    """
    Option B fallback: use Whisper timing data.
    A word is likely a filler if:
      - It's the first word in the recording, OR
      - Preceded by a gap > 0.4s (hesitation before speaking)
    """
    idx = all_words.index(word_data)
    if idx == 0:
        return True
    gap_before = word_data.get('start', 0) - all_words[idx - 1].get('end', 0)
    return gap_before > 0.4


def detect_fillers(words: List[Dict], transcript: str) -> List[Dict]:
    """
    Detect filler words using a two-stage approach:
      1. Hard fillers → always flagged
      2. Soft fillers → spaCy dependency parse (primary) +
                        position/pause heuristics (secondary)
    Returns a list of dicts: [{word, start_time}] for each detected filler.
    """
    detected: List[Dict] = []

    # --- Stage 1: Hard fillers (no context needed) ---
    for word_data in words:
        w = re.sub(r'[^\w]', '', word_data.get('word', '').lower().strip())
        if w in HARD_FILLERS:
            detected.append({'word': w, 'start_time': word_data.get('start', 0)})

    # --- Stage 2: Soft fillers — parse full transcript with spaCy ---
    doc = nlp(transcript)

    # Build a per-token decision map keyed by token index for accuracy
    token_decisions: Dict[int, bool] = {}
    for token in doc:
        w = token.text.lower().strip()
        if w in SOFT_FILLERS:
            token_decisions[token.i] = is_soft_filler_contextual(token)

    # Match Whisper words to spaCy tokens in order
    spacy_tokens = [t for t in doc if t.text.lower().strip() in SOFT_FILLERS]
    spacy_idx = 0  # pointer into spacy_tokens

    for word_data in words:
        w = re.sub(r'[^\w]', '', word_data.get('word', '').lower().strip())
        if w not in SOFT_FILLERS:
            continue

        # Advance spaCy pointer to find matching token
        matched_decision = None
        while spacy_idx < len(spacy_tokens):
            token = spacy_tokens[spacy_idx]
            if token.text.lower().strip() == w:
                matched_decision = token_decisions.get(token.i)
                spacy_idx += 1
                break
            spacy_idx += 1

        if matched_decision is None:
            matched_decision = is_soft_filler_position(word_data, words)

        if matched_decision:
            detected.append({'word': w, 'start_time': word_data.get('start', 0)})

    # Sort by time so they appear in order
    detected.sort(key=lambda x: x['start_time'])
    return detected


def analyze_fluency(words: List[Dict], transcript: str) -> tuple[List[Dict[str, Any]], List[Dict]]:
    """Run all fluency checks. Returns (issues, detected_fillers)."""
    issues = []

    if not words:
        return issues, []

    # 1. Filler Word Detection (spaCy + position heuristics)
    detected_fillers = detect_fillers(words, transcript)
    filler_words_found = [f['word'] for f in detected_fillers]

    if filler_words_found:
        filler_freq: Dict[str, int] = {}
        for w in filler_words_found:
            filler_freq[w] = filler_freq.get(w, 0) + 1
        top_fillers = ", ".join(
            f"{k} ({v}x)" for k, v in sorted(filler_freq.items(), key=lambda x: -x[1])[:5]
        )
        issues.append({
            "title": "FILLER WORDS",
            "errorText": f"{len(filler_words_found)} filler words detected",
            "explanation": f"You used {len(filler_words_found)} filler words: {top_fillers}. "
                           "This interrupts flow and makes you sound less confident.",
            "suggestions": [
                "Pause silently instead",
                "Take a breath before speaking",
                "Practice speaking slowly"
            ],
        })

    # 2. Long Pause Detection (gap > 1.2s between consecutive words)
    long_pauses = []
    for i in range(len(words) - 1):
        end_current = words[i].get("end", 0)
        start_next = words[i + 1].get("start", 0)
        gap = start_next - end_current
        if gap > 1.2:
            long_pauses.append(gap)

    if long_pauses:
        avg_pause = sum(long_pauses) / len(long_pauses)
        issues.append({
            "title": "PACING",
            "errorText": f"{len(long_pauses)} unnatural pauses",
            "explanation": f"Several gaps in speech were longer than 1.2 seconds "
                           f"(avg: {avg_pause:.1f}s). This suggests hesitation or lack of preparation.",
            "suggestions": [
                "Keep speaking rhythm consistent",
                "Prepare your thoughts in advance",
                "Practice transitions between ideas"
            ],
        })

    # 3. Speaking Speed (WPM)
    if len(words) > 5:
        duration = words[-1].get("end", 0) - words[0].get("start", 0)
        if duration > 0:
            wpm = (len(words) / duration) * 60
            if wpm < 100:
                issues.append({
                    "title": "SPEAKING SPEED",
                    "errorText": f"Too slow ({wpm:.0f} WPM)",
                    "explanation": "Your speaking pace is slower than the ideal 120–160 words per minute. "
                                   "This may lose audience attention.",
                    "suggestions": [
                        "Practice speaking slightly faster",
                        "Reduce long pauses",
                        "Be more confident with your material"
                    ],
                })
            elif wpm > 180:
                issues.append({
                    "title": "SPEAKING SPEED",
                    "errorText": f"Too fast ({wpm:.0f} WPM)",
                    "explanation": "Your speaking pace exceeds the ideal range. "
                                   "Speaking too quickly can reduce clarity.",
                    "suggestions": [
                        "Slow down and enunciate",
                        "Take deliberate pauses",
                        "Focus on clarity over speed"
                    ],
                })

    # 4. Word Repetition (content words used > 3 times, excluding all fillers)
    all_fillers = HARD_FILLERS | SOFT_FILLERS
    word_freq: Dict[str, int] = {}
    for word_data in words:
        w = re.sub(r'[^\w]', '', word_data.get("word", "").lower())
        if len(w) > 3 and w not in all_fillers:
            word_freq[w] = word_freq.get(w, 0) + 1

    repeated = [f"{k} ({v}x)" for k, v in word_freq.items() if v > 3]
    if repeated:
        issues.append({
            "title": "REPETITION",
            "errorText": f"{len(repeated)} words overused",
            "explanation": f"You repeated certain words too frequently: {', '.join(repeated[:3])}. "
                           "This suggests limited vocabulary.",
            "suggestions": [
                "Use synonyms",
                "Expand vocabulary",
                "Vary your expressions"
            ],
        })

    return issues, detected_fillers


@app.post("/analyze")
async def analyze_audio(file: UploadFile = File(...)):
    """
    Accepts an audio file (WAV/MP3/M4A), transcribes with Whisper,
    runs fluency analysis using spaCy + heuristics, returns structured JSON.
    """
    suffix = os.path.splitext(file.filename or "audio.wav")[1] or ".wav"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(await file.read())
        tmp_path = tmp.name

    try:
        result = model.transcribe(
            tmp_path,
            word_timestamps=True,
            language="en",
            initial_prompt="Um, uh, hmm, er, ah, like, you know, basically, actually, so, well, right, okay, yeah.",
            condition_on_previous_text=False,
            prepend_punctuations="",
            append_punctuations="",
        )

        all_words = []
        for segment in result.get("segments", []):
            for word in segment.get("words", []):
                all_words.append({
                    "word": word.get("word", "").strip(),
                    "start": word.get("start", 0),
                    "end": word.get("end", 0),
                })

        transcript = result.get("text", "").strip()
        fluency_issues, detected_fillers = analyze_fluency(all_words, transcript)

        return {
            "transcript": transcript,
            "fluency_issues": fluency_issues,
            "detected_fillers": detected_fillers,
            "word_count": len(all_words),
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Analysis failed: {str(e)}")

    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


@app.get("/health")
async def health_check():
    return {"status": "ok", "model": "whisper-base+spacy"}
