# Audio fixtures

Drop WAV files here — one for each case the engine must handle. These are
not checked into git (see `.gitignore`); record them yourself or hand them to
a collaborator with a clear accent.

Recording guidance: phone recorder app → export as mono 16kHz WAV (or any
format ffmpeg can decode — the engine resamples internally).

## Required fixtures

| Filename | What to record | What the engine should do |
|---|---|---|
| `silence.wav` | 5 seconds of silence | overall_score ≤ 20 |
| `perfect_speech.wav` | "I think this is a rice dish" (clearly) | overall_score ≥ 80 |
| `think_as_fink.wav` | "I fink it is correct" | flag /θ/→/f/ on "think" |
| `rice_as_lice.wav` | "I want some lice" | flag /r/→/l/ on "rice" |
| `very_as_wery.wav` | "This is wery good" | flag /v/→/w/ on "very" |
| `this_as_dis.wav` | "Dis is a book" | flag /ð/→/d/ on "this" |
| `short_utterance.wav` | one word, <300ms | per-word score: null |
| `proper_noun.wav` | "Ayesha went home" | "Ayesha" → score: null |

## Running the tests

```bash
cd pronunciation_engine
uvicorn api:app --port 8001 &      # start the engine
pytest tests/                       # run unit + fixture tests
```

The fixture tests send each WAV to the running engine and assert on the
response. Unit tests run without the engine or audio.
