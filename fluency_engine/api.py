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
nlp = spacy.load("en_core_web_md")
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

# POS tags that always indicate content use (never a filler)
CONTENT_POS = {'VERB', 'NOUN', 'ADJ', 'PROPN', 'NUM'}

# Dependency labels where the word is a required argument of its head
REQUIRED_DEPS = {'dobj', 'attr', 'acomp', 'oprd', 'npadvmod', 'nsubj', 'nsubjpass', 'pobj'}


def is_soft_filler_contextual(token) -> bool:
    """
    Generic syntactic integration test.

    A soft filler IS a filler (returns True) if it is syntactically
    detached — i.e., removing it would NOT break the sentence.

    A soft filler is NOT a filler (returns False) if it has dependents,
    is a required argument, or modifies an ADJ/ADV/VERB as an intensifier.
    """
    dep = token.dep_
    pos = token.pos_
    head_pos = token.head.pos_

    # ---- Gate 1: Content POS → never a filler ----
    if pos in CONTENT_POS:
        return False

    # ---- Gate 2: Has meaningful children → doing grammatical work ----
    meaningful_children = [c for c in token.children if c.dep_ != 'punct']
    if meaningful_children:
        # Special case: preposition with an object → content
        # "looks like a dog" — 'like' has pobj 'dog'
        return False

    # ---- Gate 3: Required argument of its head → NOT filler ----
    # e.g. "turn right", "did well", "looks right"
    if dep in REQUIRED_DEPS:
        return False

    # ---- Gate 4: Interjection / discourse marker → always filler ----
    if dep in {'intj', 'discourse'}:
        return True

    # ---- Gate 5: Intensifier / manner adverb → NOT filler ----
    # "so tired", "actually works", "really good", "literally exploded"
    if dep == 'advmod' and head_pos in {'ADJ', 'ADV', 'VERB'}:
        return False

    # ---- Gate 6: Sentence-initial conjunction/marker → filler ----
    # "So, I went..."  "Well, I think..."
    if dep in {'cc', 'mark'} and token.i <= 1:
        return True

    # ---- Gate 7: ROOT with no children at sentence start → filler ----
    # Standalone "Okay." / "Right." / "Yeah." at sentence start
    if dep == 'ROOT' and token.i <= 1 and not meaningful_children:
        return True

    # ---- Gate 8: Preposition with no object → hedge/filler use ----
    # "It was, like, crazy" — 'like' tagged prep with no pobj
    if dep == 'prep':
        has_object = any(c.dep_ in {'pobj', 'pcomp'} for c in token.children)
        if not has_object:
            return True
        return False

    # ---- Gate 9: advmod that is NOT modifying content → likely filler ----
    # Catches hedge adverbs: "basically, ..." "actually, ..."
    # (content modifiers already handled by Gate 5)
    if dep == 'advmod' and head_pos not in {'ADJ', 'ADV', 'VERB'}:
        return True

    # Conservative default — don't flag uncertain cases
    return False


def get_pause_before(word_data: Dict, all_words: List[Dict]) -> float:
    """
    Return the silence gap (seconds) immediately before this word.
    Returns a large value for the first word to indicate a natural pause.
    """
    idx = all_words.index(word_data)
    if idx == 0:
        return 1.0  # first word always has a "pause" before it
    return word_data.get('start', 0) - all_words[idx - 1].get('end', 0)


def detect_fillers(words: List[Dict], transcript: str) -> List[Dict]:
    """
    Detect filler words using a two-stage approach:
      1. Hard fillers → always flagged (no context needed)
      2. Soft fillers → spaCy syntactic integration test (primary) +
                        two-signal confirmation via pause/position (secondary)

    A soft filler is only flagged when BOTH signals agree, unless the
    syntactic signal is very strong (intj/discourse dep label).
    """
    detected: List[Dict] = []

    # --- Stage 1: Hard fillers (no context needed) ---
    for word_data in words:
        w = re.sub(r'[^\w]', '', word_data.get('word', '').lower().strip())
        if w in HARD_FILLERS:
            detected.append({'word': w, 'start_time': word_data.get('start', 0)})

    # --- Stage 2: Soft fillers — parse full transcript with spaCy ---
    doc = nlp(transcript)

    # Build per-token decision map: token_index → (is_filler, dep_label)
    token_decisions: Dict[int, tuple] = {}
    for token in doc:
        w = token.text.lower().strip()
        if w in SOFT_FILLERS:
            is_filler = is_soft_filler_contextual(token)
            token_decisions[token.i] = (is_filler, token.dep_)

    # Match Whisper words to spaCy tokens in order
    spacy_tokens = [t for t in doc if t.text.lower().strip() in SOFT_FILLERS]
    spacy_idx = 0  # pointer into spacy_tokens

    for word_data in words:
        w = re.sub(r'[^\w]', '', word_data.get('word', '').lower().strip())
        if w not in SOFT_FILLERS:
            continue

        # Advance spaCy pointer to find matching token
        spacy_says_filler = None
        dep_label = None
        while spacy_idx < len(spacy_tokens):
            token = spacy_tokens[spacy_idx]
            if token.text.lower().strip() == w:
                decision = token_decisions.get(token.i)
                if decision is not None:
                    spacy_says_filler, dep_label = decision
                spacy_idx += 1
                break
            spacy_idx += 1

        # Secondary signal: pause before the word
        pause = get_pause_before(word_data, words)
        has_pause = pause > 0.3

        # Secondary signal: sentence-initial position
        is_initial = (words.index(word_data) == 0)

        # --- Two-signal confirmation ---
        # Strong syntactic signal (intj/discourse) — flag even without pause
        if dep_label in {'intj', 'discourse'}:
            detected.append({'word': w, 'start_time': word_data.get('start', 0)})
        # spaCy says filler AND secondary signal confirms
        elif spacy_says_filler and (has_pause or is_initial):
            detected.append({'word': w, 'start_time': word_data.get('start', 0)})
        # spaCy says filler but no secondary signal — still flag if ROOT/cc/mark
        # at sentence start (these are almost always fillers)
        elif spacy_says_filler and dep_label in {'ROOT', 'cc', 'mark'}:
            detected.append({'word': w, 'start_time': word_data.get('start', 0)})
        # Fallback: spaCy had no match, use pause-only heuristic
        elif spacy_says_filler is None and has_pause:
            detected.append({'word': w, 'start_time': word_data.get('start', 0)})

    # Sort by time so they appear in order
    detected.sort(key=lambda x: x['start_time'])
    return detected


def build_annotated_transcript(all_words: List[Dict], detected_fillers: List[Dict]) -> str:
    """
    Reconstruct the transcript from Whisper word list, wrapping exact detected filler
    instances with [F]...[/F] markers.

    Uses start_time to match filler instances precisely — so if 'like' appears twice
    but only the second occurrence was detected as a filler, only the second is marked.
    """
    # Build a set of start_times for detected fillers (as rounded floats for matching)
    filler_times = {round(f['start_time'], 2) for f in detected_fillers}

    parts = []
    for word_data in all_words:
        word = word_data.get('word', '')
        start = round(word_data.get('start', 0), 2)
        clean = re.sub(r'[^\w]', '', word.lower().strip())

        # Match this word instance to a detected filler by start_time
        if start in filler_times and (clean in HARD_FILLERS or clean in SOFT_FILLERS):
            parts.append(f'[F]{word.strip()}[/F]')
            filler_times.discard(start)  # consume so duplicates don't double-match
        else:
            parts.append(word.strip())

    return ' '.join(parts)


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
        annotated_transcript = build_annotated_transcript(all_words, detected_fillers)

        return {
            "transcript": transcript,
            "annotated_transcript": annotated_transcript,
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
