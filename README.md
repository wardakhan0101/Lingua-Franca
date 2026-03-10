# Lingua Franca

An AI-powered mobile app for improving spoken English through real-time conversational practice, speech analysis, and gamified progress tracking.

Built with **Flutter** (frontend) and **Python FastAPI** (backend).

---

## Features

### AI Chatbot
- Voice-first conversational practice powered by **Ollama** (Llama 3.2 3B)
- Speak via microphone or type — responses are generated in real-time
- Built-in **homophone correction** engine for more accurate speech-to-text

### Timed Presentation Practice
- Record yourself speaking on any topic with a configurable timer (15s – 5min)
- Live transcript powered by **Deepgram** streaming STT
- After recording, get a combined **grammar + fluency analysis report**

### Fluency Analysis
- Audio is sent to a custom **Fluency Engine** backend
- Transcribed with **OpenAI Whisper** and analyzed with **spaCy** NLP
- Detects filler words (uh, um, like, basically, etc.) with context-aware filtering
- Evaluates speech speed, pacing consistency, and long pauses
- Filler words highlighted directly in the annotated transcript

### Grammar Analysis
- Text is checked via a custom **Cloud Run Grammar API**
- Shows original vs corrected text, per-mistake cards with severity, suggestions, and category breakdown

### Accent Analysis
- Custom **Accent Engine** backend for pronunciation assessment
- Compares user speech against standard pronunciation models

### Dashboard & Gamification
- Personalized home screen with progress stats (fluency, grammar, vocabulary)
- Streak tracking, achievement badges, and daily activity indicators
- Bottom navigation across Home, Chat, Practice, and Profile

### Authentication
- Firebase Auth: email/password sign-up, login, forgot password
- Auth state persistence and session management
- User profiles with Firestore storage

### Progress Storage
- All analysis results (fluency + grammar) are stored in **Cloud Firestore**
- Historical data powers the dashboard analytics

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| **Frontend** | Flutter (Dart) |
| **AI Chat** | Ollama (Llama 3.2 3B) |
| **Live STT** | Deepgram (streaming) |
| **Fluency Backend** | Python FastAPI, OpenAI Whisper, spaCy |
| **Accent Backend** | Python FastAPI, Torchaudio |
| **Grammar** | Custom Cloud Run API |
| **Auth & Storage** | Firebase Auth, Cloud Firestore |
| **Deployment** | Google Cloud Run (backend), Docker |

---

## Project Structure

```
lib/
├── main.dart                           # App entry point & auth wrapper
├── screens/
│   ├── login_screen.dart               # Login
│   ├── signup_screen.dart              # Sign up
│   ├── forgot_password_screen.dart     # Password reset
│   ├── home_screen.dart                # Dashboard with stats & gamification
│   ├── profile_screen.dart             # User profile
│   ├── chat_screen.dart                # AI chatbot (Ollama + voice input)
│   ├── timed_presentation_screen.dart  # Timed speaking practice (Deepgram)
│   ├── fluency_screen.dart             # Fluency analysis report
│   ├── grammar_report_screen.dart      # Grammar analysis report
│   ├── homophone_corrector.dart        # STT homophone correction engine
│   ├── speech_recognition_screen.dart  # Standalone speech recognition
│   ├── native_stt_screen.dart          # On-device STT (Sherpa-ONNX)
│   └── developers_screen.dart          # About / developers info
└── services/
    ├── auth_service.dart               # Firebase authentication
    ├── audio_recorder_service.dart      # Audio recording & file I/O
    ├── stt_service.dart                # Speech-to-text service bridge
    ├── grammar_api_service.dart        # Grammar API client
    └── analysis_storage_service.dart   # Firestore storage for results

fluency_engine/                         # Python backend
├── api.py                              # FastAPI server (Whisper + spaCy)
├── requirements.txt                    # Python dependencies
├── Dockerfile                          # Container config
└── README.md                           # Deployment guide

Accent_engine/                          # Python backend for pronunciation
├── main.py                             # FastAPI server
├── requirements.txt                    # Python dependencies
└── ...
```

---

## Getting Started

### Prerequisites
- Flutter SDK (≥ 3.7.2)
- A Firebase project with Auth & Firestore enabled
- Python 3.10+ and `ffmpeg` (for the backend)

### 1. Clone & Install Flutter Dependencies
```bash
git clone https://github.com/wardakhan0101/FYP-Project.git
cd FYP-Project
flutter pub get
```

### 2. Firebase Setup
Follow the detailed guide in [FIREBASE_SETUP.md](FIREBASE_SETUP.md), or quick-start:
```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

### 3. Environment Variables
Copy `.env.example` to `.env` and fill in your keys:
```
STT=your_deepgram_api_key
FLUENCY_API_URL=https://your-cloud-run-url.run.app
OLLAMA_URL=http://192.168.x.x:11434/api/chat
```

### 3.5. Setup Ollama
Ensure you have Ollama installed and the `llama3.2:3b` model downloaded:
```bash
ollama run llama3.2:3b
```

### 4. Run the App
```bash
flutter run
```

### 5. Run the Fluency Engine (Backend)
```bash
cd fluency_engine
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
uvicorn api:app --reload --port 8000
```

For production deployment to **Google Cloud Run**, see [fluency_engine/README.md](fluency_engine/README.md).

---

## API Reference (Fluency Engine)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/analyze` | `POST` | Upload audio file → returns transcript, annotated transcript, filler word list, and fluency issues |
| `/health` | `GET` | Health check — returns `{"status": "ok", "model": "whisper-base"}` |

---

## Platform Support

- Android
