from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import whisper
import spacy
import tempfile
import os
import re
from typing import List, Dict, Any, Set, Tuple, Optional

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
    'right', 'okay', 'well', 'yeah',
    'sort', 'kind', 'mean'
}

# Multi-word filler phrases — matched using a skip-gram window that ignores
# punctuation tokens between words (e.g. "you , know" still matches "you know")
MULTI_WORD_FILLERS: List[tuple] = [
    ('you', 'know'),
    ('i', 'mean'),
    ('you', 'know', 'what'),
]

# POS tags that always indicate content use (never a filler)
CONTENT_POS = {'VERB', 'NOUN', 'ADJ', 'PROPN', 'NUM'}

# Dependency labels where the word is a required argument of its head
REQUIRED_DEPS = {'dobj', 'attr', 'acomp', 'oprd', 'npadvmod', 'nsubj', 'nsubjpass', 'pobj'}


def clean_transcript_for_spacy(transcript: str) -> str:
    """
    [Option 1] Strip Whisper's aggressively injected commas and normalise
    spacing before passing the transcript to spaCy.

    Whisper emits things like "So , I was thinking" or "actually , let's go"
    where the space-comma-space pattern breaks spaCy's sentence boundary
    detection and its POS/dep tagging for sentence-initial markers.

    Removing these injected comma tokens gives spaCy a natural sentence to
    parse, which significantly improves dep label accuracy for 'So', 'actually',
    'well', etc.
    """
    # Remove isolated commas (≥1 space on both sides, or at sentence boundaries)
    cleaned = re.sub(r'\s,\s', ' ', transcript)
    # Collapse any double spaces left behind
    cleaned = re.sub(r' +', ' ', cleaned).strip()
    return cleaned


def is_soft_filler_contextual(token, doc) -> bool:
    """
    Generic syntactic integration test.

    A soft filler IS a filler (returns True) if it is syntactically
    detached — i.e., removing it would NOT break the sentence.

    A soft filler is NOT a filler (returns False) if it has dependents,
    is a required argument, or modifies an ADJ/ADV/VERB as an intensifier.

    The `doc` argument is passed explicitly so Gate 5's comma check can
    reference the document without a module-level variable.
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
        return False

    # ---- Gate 3: Required argument of its head → NOT filler ----
    if dep in REQUIRED_DEPS:
        return False

    # ---- Gate 4: Interjection / discourse marker → always filler ----
    if dep in {'intj', 'discourse'}:
        return True

    # ---- Gate 5: Intensifier / manner adverb ----
    # "so tired" / "actually works" → NOT filler (mid-sentence content modifier)
    # "So, I went..." / "Actually, let's go..." → IS filler
    #
    # Because we pre-clean the transcript (Option 1), sentence-initial discourse
    # markers won't have a spurious comma between them and the next word, so
    # spaCy's sentence boundary detection is reliable here.
    if dep == 'advmod' and head_pos in {'ADJ', 'ADV', 'VERB'}:
        rel_pos = token.i - token.sent.start
        # Near start of sentence → discourse marker
        if rel_pos <= 1:
            return True
        # Surrounded by commas in the original (cleaned) doc → hedge/discourse
        if token.i > 0 and token.i < len(doc) - 1:
            if doc[token.i - 1].text == ',' and doc[token.i + 1].text == ',':
                return True
        return False

    # ---- Gate 6: Sentence-initial conjunction/marker → filler ----
    # "So I went..."  "Well I think..."
    if dep in {'cc', 'mark'} and (token.i - token.sent.start) <= 1:
        return True

    # ---- Gate 7: ROOT with no children at sentence start → filler ----
    # Standalone "Okay." / "Right." / "Yeah."
    if dep == 'ROOT' and (token.i - token.sent.start) <= 1 and not meaningful_children:
        return True

    # ---- Gate 8: Preposition with no object → hedge/filler use ----
    # "It was like crazy" — 'like' tagged prep with no pobj
    if dep == 'prep':
        has_object = any(c.dep_ in {'pobj', 'pcomp'} for c in token.children)
        if not has_object:
            return True
        return False

    # ---- Gate 9: advmod NOT modifying content → likely filler ----
    # Catches hedge adverbs: "basically ..." "actually ..." when head is not adj/adv/verb
    if dep == 'advmod' and head_pos not in {'ADJ', 'ADV', 'VERB'}:
        return True

    # Conservative default — don't flag uncertain cases
    return False


def get_pause_before(word_data: Dict, all_words: List[Dict]) -> float:
    """Return the silence gap (seconds) immediately before this word."""
    idx = all_words.index(word_data)
    if idx == 0:
        return 1.0
    return word_data.get('start', 0) - all_words[idx - 1].get('end', 0)


def build_char_offset_map(words: List[Dict]) -> List[Tuple[int, int, int]]:
    """
    [Option 4] Build a character-offset map for the Whisper word list so that
    spaCy token positions (character offsets) can be mapped back to Whisper
    word indices without relying on sequential integer alignment.

    Returns a list of (char_start, char_end, word_idx) tuples, representing
    where each Whisper word sits in the reconstructed transcript string.

    Because we reconstruct the transcript by joining words with single spaces,
    the character offsets are deterministic and independent of Whisper's own
    timing data.
    """
    offset_map: List[Tuple[int, int, int]] = []
    cursor = 0
    for idx, word_data in enumerate(words):
        text = word_data.get('word', '').strip()
        if not text:
            # skip empty/punctuation-only tokens from Whisper
            if idx > 0:
                cursor += 1  # account for the space separator
            continue
        start = cursor
        end = cursor + len(text)
        offset_map.append((start, end, idx))
        cursor = end + 1  # +1 for the space between words
    return offset_map


def find_whisper_idx_by_char_offset(
    char_start: int, char_end: int, offset_map: List[Tuple[int, int, int]]
) -> Optional[int]:
    """
    Given a spaCy token's character span, return the corresponding Whisper
    word index by finding the offset_map entry that overlaps most.
    """
    for (ws, we, widx) in offset_map:
        # An overlap exists when the spans share any characters
        if ws < char_end and we > char_start:
            return widx
    return None


def detect_fillers(words: List[Dict], transcript: str) -> List[Dict]:
    """
    Detect filler words using a four-stage approach:

      1. Hard fillers   → always flagged (phonetic hesitations, no context needed)
      2. Multi-word     → skip-gram window that ignores punctuation between words
                          [Option 3]
      3. Soft fillers   → spaCy syntactic integration test on a comma-cleaned
                          transcript [Option 1], with decisions mapped back to
                          Whisper words via character offsets [Option 4].
                          spaCy's verdict is trusted directly — no secondary
                          pause confirmation required [Option 2].
      4. Timing fallback → if spaCy couldn't find a match, fall back to pause
                           signal alone (catches edge cases).
    """
    detected: List[Dict] = []
    claimed_indices: Set[int] = set()

    # --- Stage 1: Hard fillers (no context needed) ---
    for idx, word_data in enumerate(words):
        w = re.sub(r'[^\w]', '', word_data.get('word', '').lower().strip())
        if w in HARD_FILLERS:
            detected.append({
                'word': w,
                'start_time': word_data.get('start', 0),
                'word_indices': [idx]
            })
            claimed_indices.add(idx)

    # --- Stage 2: Multi-word fillers — skip-gram window [Option 3] ---
    # Build a list of (whisper_idx, clean_word) for non-empty, non-punctuation tokens
    content_words = []
    for i, w_data in enumerate(words):
        clean = re.sub(r'[^\w]', '', w_data.get('word', '').lower().strip())
        if clean:  # skip pure-punctuation or empty tokens
            content_words.append((i, clean))

    for phrase in MULTI_WORD_FILLERS:
        phrase_len = len(phrase)
        for vi in range(len(content_words) - phrase_len + 1):
            window_indices = [content_words[vi + j][0] for j in range(phrase_len)]
            window_words = [content_words[vi + j][1] for j in range(phrase_len)]

            if any(idx in claimed_indices for idx in window_indices):
                continue

            if tuple(window_words) == phrase:
                phrase_text = ' '.join(phrase)
                detected.append({
                    'word': phrase_text,
                    'start_time': words[window_indices[0]].get('start', 0),
                    'word_indices': window_indices
                })
                for idx in window_indices:
                    claimed_indices.add(idx)

    # --- Stage 3: Soft fillers via spaCy + character offset alignment ---

    # [Option 1] Clean Whisper's injected commas before spaCy parse
    clean_text = clean_transcript_for_spacy(transcript)
    doc = nlp(clean_text)

    # [Option 4] Build char-offset map so spaCy token positions (token.idx = char offset
    # into clean_text) map back to Whisper word indices.
    #
    # We walk clean_text forward, searching for each Whisper word's text in order.
    # Pure punctuation tokens (commas Whisper emitted as standalone entries) are skipped
    # because they were stripped in clean_transcript_for_spacy and don't appear in
    # clean_text at all.
    char_to_whisper: Dict[int, int] = {}
    search_pos = 0

    for widx, word_data in enumerate(words):
        raw_word = word_data.get('word', '').strip()
        # Skip pure-punctuation Whisper tokens — they don't exist in clean_text
        if not re.sub(r'[^\w]', '', raw_word.lower()):
            continue
        idx_in_clean = clean_text.find(raw_word, search_pos)
        if idx_in_clean == -1:
            # Fallback: try lowercase match
            idx_in_clean = clean_text.lower().find(raw_word.lower(), search_pos)
        if idx_in_clean != -1:
            char_to_whisper[idx_in_clean] = widx
            search_pos = idx_in_clean + len(raw_word)

    def whisper_idx_for_token(token) -> Optional[int]:
        """Return Whisper word index for this spaCy token via char offset."""
        return char_to_whisper.get(token.idx)


    # Collect spaCy decisions for every soft filler token
    # Map: whisper_idx → (is_filler, dep_label)
    spacy_decisions: Dict[int, Tuple[bool, str]] = {}

    for token in doc:
        w = token.text.lower().strip()
        if w not in SOFT_FILLERS:
            continue
        widx = whisper_idx_for_token(token)
        if widx is None:
            continue
        if widx in claimed_indices:
            continue
        is_filler = is_soft_filler_contextual(token, doc)
        spacy_decisions[widx] = (is_filler, token.dep_)

    # Apply decisions to Whisper words
    for word_idx, word_data in enumerate(words):
        if word_idx in claimed_indices:
            continue

        w = re.sub(r'[^\w]', '', word_data.get('word', '').lower().strip())
        if w not in SOFT_FILLERS:
            continue

        decision = spacy_decisions.get(word_idx)

        # [Option 2] Trust spaCy's verdict directly — no pause confirmation needed.
        # The secondary gate was rejecting valid fillers when speech was fast
        # (small pause) or mid-sentence (is_initial=False).
        if decision is not None:
            is_filler, dep_label = decision
            if is_filler:
                detected.append({
                    'word': w,
                    'start_time': word_data.get('start', 0),
                    'word_indices': [word_idx]
                })
                claimed_indices.add(word_idx)
        else:
            # Stage 4: Timing-only fallback when spaCy had no match
            # (e.g. the char offset didn't align due to a Whisper grouping quirk)
            pause = get_pause_before(word_data, words)
            if pause > 0.3:
                detected.append({
                    'word': w,
                    'start_time': word_data.get('start', 0),
                    'word_indices': [word_idx]
                })
                claimed_indices.add(word_idx)

    # Sort by time so they appear in transcript order
    detected.sort(key=lambda x: x['start_time'])
    return detected


def build_annotated_transcript(all_words: List[Dict], detected_fillers: List[Dict]) -> str:
    """
    Reconstruct the transcript from Whisper word list, wrapping detected filler
    instances with [F]...[/F] markers using exact word indices.
    """
    single_indices: Set[int] = set()
    multi_starts: Dict[int, int] = {}  # first_index → span length

    for f in detected_fillers:
        indices = f.get('word_indices', [])
        if not indices:
            continue
        if len(indices) > 1:
            multi_starts[indices[0]] = len(indices)
        else:
            single_indices.add(indices[0])

    parts = []
    i = 0
    while i < len(all_words):
        word = all_words[i].get('word', '').strip()

        if i in multi_starts:
            span_len = multi_starts[i]
            phrase_words = [
                all_words[i + j].get('word', '').strip()
                for j in range(min(span_len, len(all_words) - i))
            ]
            parts.append(f'[F]{" ".join(phrase_words)}[/F]')
            i += span_len
            continue

        if i in single_indices:
            parts.append(f'[F]{word}[/F]')
        else:
            parts.append(word)
        i += 1

    return ' '.join(parts)


def analyze_fluency(words: List[Dict], transcript: str) -> tuple[List[Dict[str, Any]], List[Dict]]:
    """Run all fluency checks. Returns (issues, detected_fillers)."""
    issues = []

    if not words:
        return issues, []

    # 1. Filler Word Detection
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
                text = word.get("word", "").strip()
                # Split grouped tokens Whisper may emit (e.g. "you know" as one entry)
                for subtext in text.split():
                    all_words.append({
                        "word": subtext,
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
