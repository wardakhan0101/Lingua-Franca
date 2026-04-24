import io
import time
import edge_tts
from fastapi import FastAPI
from fastapi.responses import Response
from pydantic import BaseModel

app = FastAPI()

# accent key -> Microsoft Neural voice.
# The 6 explicit keys are what scenario_chat_screen.dart sends after the
# dropdown expansion. The 3 bare-accent keys are legacy aliases so the dev-only
# accent_test_screen.dart keeps working without modification (per CLAUDE.md rule
# against touching *test* screens).
VOICE_MAP = {
    "american_female":  "en-US-JennyNeural",
    "american_male":    "en-US-GuyNeural",
    "british_female":   "en-GB-LibbyNeural",
    "british_male":     "en-GB-RyanNeural",
    "pakistani_female": "en-IN-NeerjaNeural",
    "pakistani_male":   "en-IN-PrabhatNeural",
    "american":         "en-US-JennyNeural",
    "british":          "en-GB-LibbyNeural",
    "pakistani":        "en-IN-NeerjaNeural",
}


class TTSRequest(BaseModel):
    text: str
    accent: str


@app.get("/")
def health_check():
    return {
        "status": "TTS server is running",
        "engine": "edge-tts",
        "available_accents": sorted(VOICE_MAP.keys()),
    }


@app.post("/synthesize")
async def synthesize(request: TTSRequest):
    try:
        start_time = time.time()
        accent = request.accent.lower()
        text = request.text.strip()

        if not text:
            print("[TTS] Request rejected: Empty text.")
            return Response(content="Text cannot be empty", status_code=400)

        if text[-1] not in ".!?":
            text += "."

        voice = VOICE_MAP.get(accent)
        if voice is None:
            print(f"[TTS] Request rejected: Accent '{accent}' not in VOICE_MAP.")
            return Response(
                content=f"Invalid accent: '{accent}'. Valid options: {sorted(VOICE_MAP.keys())}",
                status_code=400,
            )

        print(f"[TTS] Step 1: Resolved accent '{accent}' -> voice '{voice}'")

        print(f"[TTS] Step 2: Streaming synthesis for: '{text}'")
        audio_buffer = io.BytesIO()
        communicate = edge_tts.Communicate(text, voice)
        async for chunk in communicate.stream():
            if chunk["type"] == "audio":
                audio_buffer.write(chunk["data"])

        audio_buffer.seek(0)
        audio_bytes = audio_buffer.read()

        if not audio_bytes:
            raise RuntimeError("edge-tts returned no audio data")

        print(f"[TTS] Step 3: Received {len(audio_bytes)} bytes of MP3 audio.")

        duration = time.time() - start_time
        print(f"[TTS] SUCCESS: Generation complete in {duration:.2f}s")

        return Response(content=audio_bytes, media_type="audio/mpeg")

    except Exception as e:
        import traceback
        print("\n" + "=" * 50)
        print("[TTS] CRITICAL ERROR DURING SYNTHESIS:")
        print(f"  Error Type: {type(e).__name__}")
        print(f"  Error Message: {str(e)}")
        print("-" * 50)
        traceback.print_exc()
        print("=" * 50 + "\n")
        return Response(content=f"Internal Server Error: {str(e)}", status_code=500)
