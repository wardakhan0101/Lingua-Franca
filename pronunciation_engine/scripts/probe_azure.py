"""One-shot Azure diagnostic — hits the API with a single fixture and dumps
the raw response. Use this to figure out why compare_with_azure.py returns 0.

Run:
    export AZURE_SPEECH_KEY="..."
    export AZURE_SPEECH_REGION="eastus"
    python3 scripts/probe_azure.py                      # default fixture
    python3 scripts/probe_azure.py perfect_speech.m4a "I think this is a rice dish"
"""
from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
import tempfile

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
ENGINE_ROOT = os.path.dirname(HERE)
AUDIO_DIR = os.path.join(ENGINE_ROOT, "tests", "audio")

AZURE_KEY = os.environ.get("AZURE_SPEECH_KEY")
AZURE_REGION = os.environ.get("AZURE_SPEECH_REGION", "eastus")


def main() -> int:
    if not AZURE_KEY:
        print("AZURE_SPEECH_KEY not set", file=sys.stderr)
        return 1

    fixture = sys.argv[1] if len(sys.argv) > 1 else "perfect_speech.m4a"
    transcript = sys.argv[2] if len(sys.argv) > 2 else "I think this is a rice dish"
    fixture_path = os.path.join(AUDIO_DIR, fixture)
    if not os.path.exists(fixture_path):
        print(f"fixture not found: {fixture_path}", file=sys.stderr)
        return 1

    print(f"region:     {AZURE_REGION}")
    print(f"key prefix: {AZURE_KEY[:6]}…  (len={len(AZURE_KEY)})")
    print(f"fixture:    {fixture}")
    print(f"transcript: {transcript!r}")
    print()

    # Convert to 16kHz mono WAV.
    wav = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    wav.close()
    subprocess.run(
        [
            "ffmpeg", "-y", "-nostdin", "-loglevel", "error",
            "-i", fixture_path,
            "-ac", "1", "-ar", "16000", "-acodec", "pcm_s16le",
            wav.name,
        ],
        check=True,
    )
    size = os.path.getsize(wav.name)
    print(f"converted wav: {size} bytes")

    config = {
        "ReferenceText": transcript,
        "GradingSystem": "HundredMark",
        "Granularity": "Phoneme",
        "EnableMiscue": True,
        "Dimension": "Comprehensive",
    }
    config_b64 = base64.b64encode(json.dumps(config).encode("utf-8")).decode("ascii")

    url = (
        f"https://{AZURE_REGION}.stt.speech.microsoft.com"
        f"/speech/recognition/conversation/cognitiveservices/v1"
        f"?language=en-US&format=detailed"
    )
    print(f"POST {url}")
    print()

    with open(wav.name, "rb") as f:
        audio = f.read()
    headers = {
        "Ocp-Apim-Subscription-Key": AZURE_KEY,
        "Content-Type": "audio/wav; codecs=audio/pcm; samplerate=16000",
        "Pronunciation-Assessment": config_b64,
        "Accept": "application/json",
    }
    r = requests.post(url, headers=headers, data=audio, timeout=60)

    print(f"HTTP {r.status_code}")
    print("--- response body (first 2000 chars) ---")
    print(r.text[:2000])

    try:
        os.remove(wav.name)
    except OSError:
        pass
    return 0 if r.status_code == 200 else 1


if __name__ == "__main__":
    sys.exit(main())
