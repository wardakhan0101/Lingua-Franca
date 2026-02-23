from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import whisper
import tempfile
import os
import re
from typing import List, Dict, Any

app = FastAPI(title="Fluency Analysis Engine", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Load Whisper model once at startup (base = good accuracy, fast enough for Cloud Run)
print("Loading Whisper model...")
model = whisper.load_model("base")
print("Whisper model loaded.")

# --- Filler Words List ---
FILLER_WORDS = {
    'um', 'uh', 'hmm', 'hm', 'er', 'ah', 'eh',
    'like', 'basically', 'actually', 'literally',
    'sort', 'kind', 'right', 'okay', 'so', 'well',
    'yeah', 'mean', 'you know', 'i mean'
}

def analyze_fluency(words: List[Dict]) -> List[Dict[str, Any]]:
    """Run all fluency checks and return a list of issue cards."""
    issues = []

    if not words:
        return issues

    # 1. Filler Word Detection
    filler_words_found = []
    for word_data in words:
        word_text = word_data.get("word", "").lower().strip()
        word_text = re.sub(r'[^\w\s]', '', word_text)
        if word_text in FILLER_WORDS:
            filler_words_found.append(word_text)

    if filler_words_found:
        frequency: Dict[str, int] = {}
        for w in filler_words_found:
            frequency[w] = frequency.get(w, 0) + 1
        top_fillers = ", ".join(
            f"{k} ({v}x)" for k, v in sorted(frequency.items(), key=lambda x: -x[1])[:5]
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

    # 4. Word Repetition (non-filler words used > 3 times)
    word_freq: Dict[str, int] = {}
    for word_data in words:
        w = re.sub(r'[^\w]', '', word_data.get("word", "").lower())
        if len(w) > 3 and w not in FILLER_WORDS:
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

    return issues


@app.post("/analyze")
async def analyze_audio(file: UploadFile = File(...)):
    """
    Accepts an audio file (WAV/MP3/M4A), transcribes with Whisper,
    runs fluency analysis, and returns a structured JSON report.
    """
    # Validate file type
    allowed_types = {"audio/wav", "audio/wave", "audio/mpeg", "audio/mp4",
                     "audio/m4a", "audio/x-m4a", "application/octet-stream"}
    if file.content_type and file.content_type not in allowed_types:
        # Be lenient — mobile apps sometimes send wrong content-type
        pass

    # Save uploaded file to a temp location (Whisper needs a file path)
    suffix = os.path.splitext(file.filename or "audio.wav")[1] or ".wav"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(await file.read())
        tmp_path = tmp.name

    try:
        # Transcribe with Whisper.
        # CRITICAL: initial_prompt biases the model to preserve filler words like um, uh, hmm.
        # Without this, Whisper silently removes them from the output.
        # condition_on_previous_text=False prevents the prompt from being appended to the transcript.
        result = model.transcribe(
            tmp_path,
            word_timestamps=True,
            language="en",
            initial_prompt="Um, uh, hmm, er, ah, like, you know, basically, actually, so, well, right, okay, yeah.",
            condition_on_previous_text=False,
            prepend_punctuations="",
            append_punctuations="",
        )

        # Flatten all word segments into a single list
        all_words = []
        for segment in result.get("segments", []):
            for word in segment.get("words", []):
                all_words.append({
                    "word": word.get("word", "").strip(),
                    "start": word.get("start", 0),
                    "end": word.get("end", 0),
                })

        transcript = result.get("text", "").strip()
        fluency_issues = analyze_fluency(all_words)

        return {
            "transcript": transcript,
            "fluency_issues": fluency_issues,
            "word_count": len(all_words),
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Analysis failed: {str(e)}")

    finally:
        # Always clean up the temp file
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


@app.get("/health")
async def health_check():
    return {"status": "ok", "model": "whisper-base"}
