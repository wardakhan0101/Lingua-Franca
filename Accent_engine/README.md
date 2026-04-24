# Accent Engine Setup (Mac & Windows)

This is the TTS backend for Lingua Franca. It runs a small FastAPI service that wraps Microsoft's free Edge neural voices via the `edge-tts` library. No API key, no account, no local AI model — the server is a thin messenger between the Flutter app and Microsoft's public voice endpoint.

## Prerequisites
- Python 3.8 or newer (no version pin — any modern Python works)
- Internet access on whichever machine runs the server (the server calls Microsoft's endpoint; the phone just talks to the server)

## Setup (macOS / Linux)

```bash
cd path/to/FYP-Project/Accent_engine

python3 -m venv venv
source venv/bin/activate

pip install --upgrade pip
pip install -r requirements.txt
```

Start the server:

```bash
uvicorn tts_service:app --host 0.0.0.0 --port 8000
```

Expect startup in under 5 seconds — there is no model to load.

## Setup (Windows / PowerShell)

```powershell
cd "path\to\FYP-Project\Accent_engine"

python -m venv venv
& "venv\Scripts\Activate.ps1"

pip install --upgrade pip
pip install -r requirements.txt
```

Start the server:

```powershell
uvicorn tts_service:app --host 0.0.0.0 --port 8000
```

## ADB Reverse (for Android testing over USB)

The Flutter client hits `http://127.0.0.1:8000`. To make that reach your laptop from a USB-connected Android device, open a second terminal and run:

```bash
# macOS / Linux
~/Library/Android/sdk/platform-tools/adb reverse tcp:8000 tcp:8000
```

```powershell
# Windows
~\AppData\Local\Android\Sdk\platform-tools\adb.exe reverse tcp:8000 tcp:8000
```

## Available voices

`GET http://127.0.0.1:8000/` returns the list of accepted accent keys. The scenario-chat dropdown sends one of these six:

| Accent key | Voice |
|---|---|
| `american_female`  | en-US-JennyNeural |
| `american_male`    | en-US-GuyNeural |
| `british_female`   | en-GB-LibbyNeural |
| `british_male`     | en-GB-RyanNeural |
| `pakistani_female` | en-IN-NeerjaNeural |
| `pakistani_male`   | en-IN-PrabhatNeural |

The bare keys `american`, `british`, `pakistani` are also accepted as aliases for the female voices (kept for backward compatibility with the dev-only `accent_test_screen.dart`).

No Pakistani English neural voice exists in any major TTS provider — Indian English (`en-IN`) is the closest regional match.

## Troubleshooting

### `Connection closed before full header was received`
The Flutter app can reach the `adb reverse` tunnel, but the FastAPI server is not running or has crashed.

**Fix:** activate the venv and restart the server:
```bash
source venv/bin/activate   # or & "venv\Scripts\Activate.ps1" on Windows
uvicorn tts_service:app --host 0.0.0.0 --port 8000
```

### `edge_tts` request fails with a network error
The server machine needs outbound internet access to Microsoft's speech endpoint. Check firewall / VPN / captive portal.
