# Pronunciation Engine

Phoneme-level pronunciation assessment for Lingua Franca. Sibling to
`fluency_engine/` and `grammar_checker/`.

## How it works

1. **Wav2Vec2 phoneme recognition** (`facebook/wav2vec2-lv-60-espeak-cv-ft`)
   runs a single forward pass on the whole audio clip and emits frame-level
   CTC logits over an eSpeak phoneme vocabulary.
2. **phonemizer (espeak-ng backend)** converts the Whisper transcript (passed
   in from `fluency_engine`) to expected phonemes per word.
3. **Needleman-Wunsch alignment** with phonologically-weighted costs (exact=0,
   same-class=0.5, different-class=1.0) aligns the two sequences.
4. **Confidence-based GOP** (Hu et al. 2015) scores each expected phoneme 0-100
   using the mean softmax posterior assigned to that phoneme's vocab id across
   the aligned frame span.
5. Per-phoneme scores aggregate to per-word scores, which aggregate to an
   overall 0-100 pronunciation score plus phoneme-level statistics.

## Setup

### Option A: Docker (recommended for collaborators)

```bash
cd pronunciation_engine
docker compose up --build
# first build downloads the ~1.2 GB Wav2Vec2 model into a named volume
```

Served at `http://localhost:8001`.

### Option B: Python 3.11 locally

Python **3.11 specifically** (torch + transformers combo for this project is
pinned to 2.2.x which builds cleanly on 3.11; 3.12 may need wheel rebuilds).

```bash
# macOS
brew install espeak-ng ffmpeg

# Ubuntu / Debian
sudo apt install espeak-ng ffmpeg libsndfile1

cd pronunciation_engine
python3.11 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python download_models.py              # downloads Wav2Vec2 once
uvicorn api:app --host 0.0.0.0 --port 8001
```

## API

### `POST /analyze`

Multipart form:
- `file` — audio (WAV/MP3/M4A)
- `transcript` — plain text string
- `whisper_words` — JSON string: `[{"word": "...", "start": 0.12, "end": 0.45}, …]`

Response:

```json
{
  "overall_score": 78,
  "per_word": [{
    "word": "think",
    "score": 42,
    "start": 1.23,
    "end": 1.58,
    "expected_phonemes": ["θ","ɪ","ŋ","k"],
    "actual_phonemes":   ["f","ɪ","ŋ","k"],
    "phoneme_scores":    [12, 94, 88, 91],
    "issues": [{
      "type": "substitution",
      "expected": "θ",
      "actual": "f",
      "position": 0,
      "expected_ipa_label": "th (as in think)",
      "hint": "Place tongue between teeth and blow air gently."
    }]
  }],
  "phoneme_stats": {
    "θ": {"expected": 4, "correct": 1, "substitutions": {"f": 3}}
  }
}
```

Words with `score: null` are skipped (too short / unknown to the dictionary,
e.g. proper nouns). A `skipped_reason` field explains why.

### `GET /health`

Returns `{"status": "ok", "model": "..."}`.

## Flutter client

Reads `PRONUNCIATION_API_URL` from `.env`. For a physical Android device on
the same Wi-Fi as your dev machine, either point the URL at your LAN IP or
run `adb reverse tcp:8001 tcp:8001` and use `http://127.0.0.1:8001`.

## Tests

```bash
pytest tests/
```

Unit tests (alignment, canonicalizer, scoring) run without audio or the model
and pass in milliseconds. Audio fixture tests are skipped until you drop WAV
files into `tests/audio/` — see `tests/audio/README.md`.
