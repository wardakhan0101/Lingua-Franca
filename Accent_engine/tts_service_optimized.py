import os
import io
import time
import numpy as np
from scipy.io import wavfile
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
print("Loading xtts_v2 model... this may take a minute.")
tts = TTS(model_name="tts_models/multilingual/multi-dataset/xtts_v2", gpu=False)

# Store reference to the underlying model and sample rate
xtts_model = tts.synthesizer.tts_model
sample_rate = tts.synthesizer.output_sample_rate

# --- Pre-calculate Speaker Latents (Optimization) ---
print("Pre-calculating speaker latents for faster generation...")
SPEAKER_LATENTS = {}
for name, wav_path in SPEAKER_WAVS.items():
    if os.path.exists(wav_path):
        print(f"  -> Processing {name}...")
        gpt_cond_latent, speaker_embedding = xtts_model.get_conditioning_latents(audio_path=[wav_path])
        SPEAKER_LATENTS[name] = {
            "gpt_cond_latent": gpt_cond_latent,
            "speaker_embedding": speaker_embedding
        }
    else:
        print(f"  !! Skipping {name} - file not found: {wav_path}")

print("Model and latents loaded. Server ready.")

# --- Request schema ---
class TTSRequest(BaseModel):
    text: str
    accent: str

# --- Health check endpoint ---
@app.get("/")
def health_check():
    return {"status": "TTS server is running (OPTIMIZED)", "cached_accents": list(SPEAKER_LATENTS.keys())}

# --- Main TTS endpoint ---
@app.post("/synthesize")
def synthesize(request: TTSRequest):
    try:
        start_time = time.time()
        accent = request.accent.lower()
        text = request.text.strip()

        if not text:
            print("[TTS] Request rejected: Empty text.")
            return Response(content="Text cannot be empty", status_code=400)

        # Add a period for smoother generation
        if text[-1] not in ".!?":
            text += "."

        if accent not in SPEAKER_LATENTS:
            print(f"[TTS] Request rejected: Accent '{accent}' not found in cached latents.")
            return Response(
                content=f"Invalid accent or latent not cached: '{accent}'.",
                status_code=400,
            )

        print(f"[TTS] Step 1: Retrieving latents for '{accent}'...")
        latents = SPEAKER_LATENTS[accent]
        
        print(f"[TTS] Step 2: Running direct model inference for: '{text}'")
        out = xtts_model.inference(
            text=text,
            language="en",
            gpt_cond_latent=latents["gpt_cond_latent"],
            speaker_embedding=latents["speaker_embedding"],
        )
        
        print("[TTS] Step 3: Formatting output to WAV...")
        audio_buffer = io.BytesIO()
        wavfile.write(audio_buffer, sample_rate, out["wav"])
        audio_buffer.seek(0)
        audio_bytes = audio_buffer.read()

        duration = time.time() - start_time
        print(f"[TTS] SUCCESS: Generation complete in {duration:.2f}s")

        return Response(content=audio_bytes, media_type="audio/wav")

    except Exception as e:
        import traceback
        print("\n" + "="*50)
        print("[TTS] CRITICAL ERROR DURING SYNTHESIS:")
        print(f"  Error Type: {type(e).__name__}")
        print(f"  Error Message: {str(e)}")
        print("-"*50)
        traceback.print_exc()
        print("="*50 + "\n")
        return Response(content=f"Internal Server Error: {str(e)}", status_code=500)
