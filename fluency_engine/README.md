# Fluency Engine — Deployment Guide

Python FastAPI service using OpenAI Whisper for speech-to-text and fluency analysis.
Replaces the Deepgram dependency in `fluency_screen.dart`.

## Prerequisites

- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) (`gcloud`) installed and authenticated
- Docker installed (for local testing)
- A Google Cloud project with billing enabled

---

## 1. Local Testing (Optional)

```bash
# From the fluency_engine/ directory
pip install -r requirements.txt

# You'll also need ffmpeg installed:
# macOS:  brew install ffmpeg
# Linux:  sudo apt install ffmpeg

uvicorn api:app --reload --port 8000
```

Test it:
```bash
curl -X POST http://localhost:8000/analyze \
  -F "file=@/path/to/your/test.wav" | python3 -m json.tool
```

---

## 2. Deploy to Google Cloud Run

### Step 1 — Set your project
```bash
gcloud config set project YOUR_PROJECT_ID
```

### Step 2 — Enable required APIs
```bash
gcloud services enable run.googleapis.com artifactregistry.googleapis.com
```

### Step 3 — Create an Artifact Registry repository
```bash
gcloud artifacts repositories create fluency-engine \
  --repository-format=docker \
  --location=us-central1
```

### Step 4 — Build and push the Docker image
```bash
# From the fluency_engine/ directory
gcloud builds submit --tag us-central1-docker.pkg.dev/YOUR_PROJECT_ID/fluency-engine/api
```
> ⚠️ This step takes ~5–10 minutes the first time (it downloads and bakes in the Whisper model).

### Step 5 — Deploy to Cloud Run
```bash
gcloud run deploy fluency-engine \
  --image us-central1-docker.pkg.dev/YOUR_PROJECT_ID/fluency-engine/api \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --memory 2Gi \
  --cpu 2 \
  --timeout 120
```

> **Memory:** Whisper base needs ~1GB RAM. 2Gi gives headroom.
> **Timeout:** 120s to handle longer audio clips.

### Step 6 — Copy your Cloud Run URL

After deployment, you'll see output like:
```
Service URL: https://fluency-engine-xxxxxxxxxx-uc.a.run.app
```

Copy this URL and add it to your Flutter app's `.env` file:
```
FLUENCY_API_URL=https://fluency-engine-xxxxxxxxxx-uc.a.run.app
```

---

## API Reference

### `POST /analyze`
- **Body:** `multipart/form-data` with field `file` (WAV/MP3/M4A)
- **Returns:**
```json
{
  "transcript": "Hello this is a test uh basically...",
  "fluency_issues": [
    {
      "title": "FILLER WORDS",
      "errorText": "2 filler words detected",
      "explanation": "You used 2 filler words: uh (1x), basically (1x)...",
      "suggestions": ["Pause silently instead", "..."]
    }
  ],
  "word_count": 42
}
```

### `GET /health`
Returns `{"status": "ok", "model": "whisper-base"}` — use this to verify the service is running.

---

## Re-deploying After Code Changes

```bash
# From fluency_engine/ directory

# 1. Build and push image WITH layer caching
# This uses cloudbuild.yaml to pull the previous image as a cache source,
# saving ~5-10 minutes on the torch, Whisper, and spaCy layers.
gcloud builds submit --config cloudbuild.yaml .

# 2. Deploy the new image to Cloud Run
gcloud run deploy fluency-engine \
  --image us-central1-docker.pkg.dev/YOUR_PROJECT_ID/fluency-engine/api:latest \
  --region us-central1
```
