"""Pre-downloads the Wav2Vec2 phoneme model into the HF cache.

Pinning the revision is recommended for reproducibility on a collaborator's
machine — HF can silently update weights. Set PRONUNCIATION_MODEL_REVISION
in the environment to a specific commit SHA if you want a hard pin; otherwise
we take the current main revision at build time (still cached afterwards).
"""
import os
from transformers import Wav2Vec2ForCTC, Wav2Vec2Processor

MODEL_ID = "facebook/wav2vec2-lv-60-espeak-cv-ft"
REVISION = os.environ.get("PRONUNCIATION_MODEL_REVISION", "main")


def main() -> None:
    print(f"Downloading {MODEL_ID}@{REVISION} …")
    Wav2Vec2Processor.from_pretrained(MODEL_ID, revision=REVISION)
    Wav2Vec2ForCTC.from_pretrained(MODEL_ID, revision=REVISION)
    print("Model cached.")


if __name__ == "__main__":
    main()
