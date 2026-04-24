# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Lingua Franca** — a Flutter app for spoken-English practice. The Flutter client talks to three independent Python FastAPI backends (fluency, grammar, accent/TTS), Firebase (Auth + Firestore), Ollama (local LLM), and Deepgram (streaming STT). Each backend lives in its own sibling folder and is deployed/run independently.

## Commands

### Flutter (root)
```bash
flutter pub get
flutter run                  # build & launch on connected device/emulator
flutter test                 # run Dart tests in test/
flutter test test/widget_test.dart   # run a single test file
flutter analyze              # lint (flutter_lints ruleset in analysis_options.yaml)
flutter clean                # wipe build/ and .dart_tool/ when gradle/pod state is bad
```

### Backend: fluency_engine/ (Whisper + spaCy, deployed to Cloud Run)
```bash
cd fluency_engine
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
uvicorn api:app --reload --port 8000
pytest tests/                          # requires audio fixtures in tests/audio/
pytest tests/test_fluency.py::test_perfect_speech   # single test
# Deploy (see fluency_engine/README.md):
gcloud builds submit --config cloudbuild.yaml .   # cached rebuild
```

### Backend: Accent_engine/ (edge-tts wrapper, local only)
Thin FastAPI service that forwards text to Microsoft's free Edge neural-voice endpoint via the `edge-tts` library. No API key, no account, no local model. Any Python 3.8+ works:
```bash
python -m venv venv && source venv/bin/activate   # or Activate.ps1 on Windows
pip install -r requirements.txt
uvicorn tts_service:app --host 0.0.0.0 --port 8000
```
The Flutter client hits `http://127.0.0.1:8000` — for a physical Android device use `adb reverse tcp:8000 tcp:8000`. Returns MP3 (`audio/mpeg`), which `MyAudioSource` in `lib/services/my_audio_source.dart` feeds into `just_audio`. Accent dropdown sends one of 6 keys (`american_female`/`male`, `british_female`/`male`, `pakistani_female`/`male`); the `VOICE_MAP` in `tts_service.py` also accepts bare `american`/`british`/`pakistani` as aliases for the female voices so the dev-only `accent_test_screen.dart` keeps working.

### Backend: grammar_checker/ (LanguageTool + T5 + spaCy)
Deployed to Cloud Run at the URL hard-coded in `lib/services/grammar_api_service.dart`. The Dart client does **not** read this from `.env` — change it in code if redeploying to a new URL.

### Environment setup before `flutter run`
The Flutter app will not start without a `.env` in the repo root (loaded in `main.dart` via `flutter_dotenv`, and declared as an asset in `pubspec.yaml`). Required keys:
- `STT` — Deepgram API key (streaming transcription)
- `FLUENCY_API_URL` — Cloud Run URL for fluency_engine
- `OLLAMA_URL` — full URL to the local Ollama `/api/chat` endpoint

On macOS, `scripts/update_env_ip.sh` auto-rewrites `OLLAMA_URL` with the Mac's current LAN IP and sets `OLLAMA_HOST=0.0.0.0` so a physical Android phone on the same Wi-Fi can reach Ollama. After editing `.env` you must fully **stop and restart** Flutter — hot reload won't re-read it. See `OLLAMA_ANDROID_SETUP.md` for the Wi-Fi vs. `adb reverse tcp:11434 tcp:11434` trade-off.

## Architecture

### Flutter client (`lib/`)
- `main.dart` → `AuthWrapper` gates the app on `FirebaseAuth.authStateChanges`; signed-in users land on `HomeScreen`, others on `LoginScreen`.
- `screens/` holds one widget per screen. The live/production flows are **home, profile, timed_presentation, scenario_chat, fluency, grammar_report, unified_report, badges, login/signup/forgot_password**. Anything with `test` in its filename (e.g. `timed_presentation_test.dart`, `chat_screen_test.dart`, `native_stt_screen_test.dart`, `sherpa_stt_test.dart`, `accent_test_screen.dart`, `model_chatbot_screen.dart`) is early-stage dev scaffolding reached only from `developers_screen.dart` — do not refactor or use as reference.
- `services/` is the single boundary to every external system. Each file owns one integration: `auth_service` (Firebase Auth), `analysis_storage_service` (Firestore writes under `users/{uid}/analyses`), `gamification_service` (XP/streak/badges, also under `users/{uid}`), `ollama_api_service`, `fluency_api_service`, `grammar_api_service`, `tts_api_service`, `stt_service` (sherpa-onnx, currently unused — see ignored-tech note), `audio_recorder_service`, `my_audio_source` (just_audio custom source for TTS playback).

### Data flow — timed presentation
`timed_presentation_screen` records with `record` + streams PCM to Deepgram for live transcript, writes raw audio to a WAV file, then POSTs the file to `FluencyApiService.analyzeAudio` and the transcript to `GrammarApiService.analyzeText`. Both results go to `unified_report_screen` and are persisted via `AnalysisStorageService`. `GamificationService.updateSessionXp` consumes the same pair to compute XP from the grammar score and annotated-transcript markers (`[P-major]`, `[S]`, `[FAST]`, `[F]`, `[P-minor]`) and to update streak/badges.

### Data flow — scenario chat
`scenario_chat_screen` loops: Deepgram STT → `OllamaApiService` for Llama 3.2 reply → `TtsApiService` (local XTTS v2) → `just_audio` playback. `_isTtsPlaying` deliberately blocks the mic during TTS to avoid audio-session conflicts. When the user ends the session, the full user transcript is run through grammar+fluency and piped into the same `unified_report_screen` + gamification path as timed presentation.

### Gamification (`gamification_service.dart`)
User doc at `users/{uid}` holds `totalXp`, `currentLevel` (B1 → B2 @ 2500 → C1 @ 7500 → C2 @ 15000), `currentStreak`, `longestStreak`, `lastActiveDate`, `totalSessions`, `badges[]`, `joinedAt`. Streak is computed by **local calendar day** difference, not a rolling 24-hour window — practicing Mon 11 PM then Tue 9 AM is a 2-day streak. Preserve this when touching streak logic.

### Fluency engine (`fluency_engine/api.py`)
Pipeline: Whisper `base` transcribe with word timestamps and a filler-priming `initial_prompt` → spaCy `en_core_web_md` → rule-based filler detection. Fillers are split into **HARD_FILLERS** (always flagged: um/uh/hmm/…) and **SOFT_FILLERS** (so/like/basically/actually/… — only flagged when syntactically detached per the gate logic in `is_soft_filler_contextual`). `clean_transcript_for_spacy` strips Whisper's injected commas before parsing because they break dep tagging for sentence-initial markers. Multi-word phrases (`you know`, `i mean`) use a skip-gram window so punctuation between tokens doesn't break the match. Do not apply brute-force fixes that re-flag grammatically-functional soft fillers — the gate system is intentional.

### Grammar engine (`grammar_checker/python_api.py`)
Three-stage pipeline: LanguageTool + spaCy + custom rules find mistakes → `vennify/t5-base-grammar-correction` polishes → output compares original vs. corrected, returns per-mistake cards with severity/suggestions/categories and a `grammar_score` consumed by gamification.

## Working conventions (from `.cursorrules`)

- **Answer first, code later.** If the user is asking for analysis or explanation, don't jump into edits.
- **Surgical fixes only.** Don't overwrite whole files or refactor adjacent code unprompted.
- **Stop when ambiguous.** Ask instead of guessing root causes.
- **Real-device testing matters.** This app is validated on a physical Redmi Note 14 and with pre-recorded audio sentences; ask how the user will test before declaring a fix done.
- **Ignored tech:** do not suggest or implement with Groq AI, sherpa-onnx, or native STT. `lib/services/stt_service.dart` and the `assets/models/*.onnx` files exist but are not wired into the production flows.
- **Ignored screens:** anything in `lib/screens/` with `test` in the filename is dev-only — don't modify or reference.
