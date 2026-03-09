import os
import io
from fastapi import FastAPI
from fastapi.responses import Response
from pydantic import BaseModel
from TTS.api import TTS

app = FastAPI()

# --- Paths to your speaker WAV files ---
# These are relative to where tts_service.py lives (inside Accent_engine/)
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

SPEAKER_WAVS = {
    "american":  os.path.join(BASE_DIR, "english18.wav"),
    "british":   os.path.join(BASE_DIR, "english188.wav"),
    "pakistani": os.path.join(BASE_DIR, "audio.wav"),
}

# --- Load model ONCE at startup (RAM optimization: load only once) ---
print("Loading xtts_v2 model... this may take a minute.")
tts = TTS(model_name="tts_models/multilingual/multi-dataset/xtts_v2", gpu=False)
print("Model loaded. Server ready.")

# --- Request schema ---
class TTSRequest(BaseModel):
    text: str
    accent: str  # 'american', 'british', or 'pakistani'

# --- Health check endpoint ---
@app.get("/")
def health_check():
    return {"status": "TTS server is running"}

# --- Main TTS endpoint ---
@app.post("/synthesize")
def synthesize(request: TTSRequest):
    accent = request.accent.lower()
    text = request.text.strip()

    if not text:
        return Response(content="Text cannot be empty", status_code=400)

    # Add a period if no punctuation is present to help XTTS v2 "close" the sentence
    if text[-1] not in ".!?":
        text += "."

    print(f"[TTS] Processing text: {text}")

    if accent not in SPEAKER_WAVS:
        return Response(
            content=f"Invalid accent '{accent}'. Choose from: american, british, pakistani.",
            status_code=400,
        )

    speaker_wav = SPEAKER_WAVS[accent]

    if not os.path.exists(speaker_wav):
        return Response(
            content=f"Speaker WAV file not found: {speaker_wav}",
            status_code=500,
        )

    # Generate audio into a BytesIO buffer
    audio_buffer = io.BytesIO()
    tts.tts_to_file(
        text=text,
        speaker_wav=speaker_wav,
        language="en",
        file_path=audio_buffer,
    )
    audio_buffer.seek(0)
    audio_bytes = audio_buffer.read()

    return Response(content=audio_bytes, media_type="audio/wav")