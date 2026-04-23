"""Wav2Vec2 phoneme recognition wrapper.

Loads `facebook/wav2vec2-lv-60-espeak-cv-ft` once at startup. Given audio,
runs a single whole-audio forward pass and exposes:
  - greedy phoneme sequence (for debug)
  - softmax posteriors per frame (for confidence-based GOP)
  - frame-level phoneme id grid
  - frame stride in seconds (so callers can convert seconds → frame indices)
"""
from __future__ import annotations

import os
from dataclasses import dataclass
from typing import List

import subprocess

import numpy as np
import torch
from transformers import Wav2Vec2ForCTC, Wav2Vec2Processor

from canonicalizer import canonicalize_phoneme

MODEL_ID = "facebook/wav2vec2-lv-60-espeak-cv-ft"
TARGET_SR = 16000
# Wav2Vec2 stride: model downsamples 16kHz input by 320× → 20 ms per frame.
FRAME_STRIDE_SECONDS = 0.02


@dataclass
class PhonemeInference:
    """Result of running Wav2Vec2 on one audio clip."""
    posteriors: np.ndarray         # shape: (num_frames, vocab_size), softmax-normalized
    greedy_ids: np.ndarray         # shape: (num_frames,), argmax over vocab
    id_to_phoneme: List[str]       # vocab lookup (canonicalized)
    blank_id: int
    num_frames: int
    frame_stride: float            # seconds per frame


class PhonemeRecognizer:
    def __init__(self, device: str | None = None):
        self.device = device or ("cuda" if torch.cuda.is_available() else "cpu")
        print(f"[pronunciation_engine] Loading Wav2Vec2 on {self.device}…")
        revision = os.environ.get("PRONUNCIATION_MODEL_REVISION", "main")
        self.processor = Wav2Vec2Processor.from_pretrained(MODEL_ID, revision=revision)
        self.model = Wav2Vec2ForCTC.from_pretrained(MODEL_ID, revision=revision).to(self.device)
        self.model.eval()

        # Build id → phoneme lookup, canonicalized so alignment comparisons work.
        vocab = self.processor.tokenizer.get_vocab()  # dict[str, int]
        inv = sorted(vocab.items(), key=lambda kv: kv[1])
        self.id_to_phoneme: List[str] = [canonicalize_phoneme(tok) for tok, _ in inv]
        # The CTC blank is the pad token in this model.
        self.blank_id = self.processor.tokenizer.pad_token_id
        print(f"[pronunciation_engine] Model ready. Vocab={len(self.id_to_phoneme)}, blank_id={self.blank_id}")

    def _load_audio(self, path: str) -> np.ndarray:
        """Decode audio to mono 16 kHz float32 via ffmpeg.

        Same pattern Whisper uses — ffmpeg is the only codec handler flexible
        enough to cover WAV/MP3/M4A/OGG/WebM without backend-per-format config.
        """
        cmd = [
            "ffmpeg",
            "-nostdin",
            "-threads", "0",
            "-i", path,
            "-f", "s16le",
            "-ac", "1",
            "-acodec", "pcm_s16le",
            "-ar", str(TARGET_SR),
            "-",
        ]
        try:
            raw = subprocess.run(
                cmd, capture_output=True, check=True
            ).stdout
        except subprocess.CalledProcessError as exc:
            raise RuntimeError(
                f"ffmpeg failed to decode {path}: {exc.stderr.decode(errors='replace')[:300]}"
            ) from exc
        audio = np.frombuffer(raw, np.int16).astype(np.float32) / 32768.0
        return audio

    def infer(self, audio_path: str) -> PhonemeInference:
        audio = self._load_audio(audio_path)
        inputs = self.processor(audio, sampling_rate=TARGET_SR, return_tensors="pt")
        input_values = inputs.input_values.to(self.device)

        with torch.no_grad():
            logits = self.model(input_values).logits  # (1, T, V)

        # Softmax over vocab for GOP scoring.
        probs = torch.softmax(logits, dim=-1).squeeze(0).cpu().numpy()
        greedy = probs.argmax(axis=-1)

        return PhonemeInference(
            posteriors=probs,
            greedy_ids=greedy,
            id_to_phoneme=self.id_to_phoneme,
            blank_id=self.blank_id,
            num_frames=probs.shape[0],
            frame_stride=FRAME_STRIDE_SECONDS,
        )

    def greedy_phoneme_sequence(self, inference: PhonemeInference) -> List[str]:
        """Collapse CTC greedy output into a phoneme sequence (drop blanks + repeats)."""
        result: List[str] = []
        prev = -1
        for fid in inference.greedy_ids:
            if fid == inference.blank_id:
                prev = -1
                continue
            if fid == prev:
                continue
            phoneme = inference.id_to_phoneme[fid]
            if phoneme:
                result.append(phoneme)
            prev = fid
        return result

    def slice_frames(
        self,
        inference: PhonemeInference,
        start_sec: float,
        end_sec: float,
        pad_frames: int = 2,
    ) -> tuple[np.ndarray, np.ndarray, int, int]:
        """Slice the posterior/greedy arrays to the time window [start_sec, end_sec]
        with ±pad_frames of padding. Used for per-word scoring.

        Returns (posteriors_slice, greedy_slice, start_frame, end_frame).
        """
        total = inference.num_frames
        sf = int(max(0, start_sec / inference.frame_stride) - pad_frames)
        ef = int(min(total, end_sec / inference.frame_stride) + pad_frames)
        sf = max(0, sf)
        ef = max(sf + 1, min(total, ef))
        return (
            inference.posteriors[sf:ef],
            inference.greedy_ids[sf:ef],
            sf,
            ef,
        )

    def greedy_in_range(
        self, inference: PhonemeInference, start_frame: int, end_frame: int
    ) -> List[str]:
        """Collapse CTC greedy within a frame range to a phoneme sequence."""
        greedy = inference.greedy_ids[start_frame:end_frame]
        result: List[str] = []
        prev = -1
        for fid in greedy:
            if fid == inference.blank_id:
                prev = -1
                continue
            if fid == prev:
                continue
            phoneme = inference.id_to_phoneme[fid]
            if phoneme:
                result.append(phoneme)
            prev = fid
        return result
