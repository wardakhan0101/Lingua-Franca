import os
import io
import time
from fastapi import FastAPI
from fastapi.responses import Response
from pydantic import BaseModel
from TTS.api import TTS

app = FastAPI()

# --- Paths to your speaker WAV files ---
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

SPEAKER_WAVS = {
    "american":  os.path.join(BASE_DIR, "english18.wav"),
    "british":   os.path.join(BASE_DIR, "english188.wav"),
    "pakistani": os.path.join(BASE_DIR, "audio.wav"),
}

# --- Load model ONCE at startup ---
print("Loading xtts_v2 model (BASIC VERSION)... this may take a minute.")
tts = TTS(model_name="tts_models/multilingual/multi-dataset/xtts_v2", gpu=False)
print("Model loaded. Server ready.")

# --- Request schema ---
class TTSRequest(BaseModel):
    text: str
    accent: str

# --- Health check endpoint ---
@app.get("/")
def health_check():
    return {"status": "TTS server is running (BASIC)"}

# --- Main TTS endpoint ---
@app.post("/synthesize")
def synthesize(request: TTSRequest):
    try:
        start_time = time.time()
        accent = request.accent.lower()
        text = request.text.strip()

        if not text:
            return Response(content="Text cannot be empty", status_code=400)

        # Add a period for smoother generation
        if text[-1] not in ".!?":
            text += "."

        print(f"[TTS] Generating (Basic): {text}")

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
        # This analyzes the WAV file every single time
        audio_buffer = io.BytesIO()
        tts.tts_to_file(
            text=text,
            speaker_wav=speaker_wav,
            language="en",
            file_path=audio_buffer,
        )
        audio_buffer.seek(0)
        audio_bytes = audio_buffer.read()

        duration = time.time() - start_time
        print(f"[TTS] Generation complete in {duration:.2f}s")

        return Response(content=audio_bytes, media_type="audio/wav")

    except Exception as e:
        import traceback
        print("[TTS] ERROR DURING BASIC SYNTHESIS:")
        traceback.print_exc()
        return Response(content=f"Internal Server Error: {str(e)}", status_code=500)
