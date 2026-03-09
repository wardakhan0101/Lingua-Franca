import os
import sys
import pytest
import ssl

# Bypass macOS SSL certificate verification for downloading the Whisper model locally
ssl._create_default_https_context = ssl._create_unverified_context

# Add the parent directory to sys.path to import api.py
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from api import analyze_fluency, model, get_audio_duration

AUDIO_DIR = os.path.join(os.path.dirname(__file__), 'audio')

def run_analysis(filename):
    """Helper to run the full pipeline on a local audio file."""
    filepath = os.path.join(AUDIO_DIR, filename)
    if not os.path.exists(filepath):
        pytest.skip(f"Audio file {filename} not found.")
    
    result = model.transcribe(
        filepath,
        word_timestamps=True,
        language="en",
        initial_prompt="Um, uh, hmm, er, ah, like, you know, basically, actually, so, well, right, okay, yeah.",
        condition_on_previous_text=False,
        prepend_punctuations="",
        append_punctuations="",
    )

    all_words = []
    for segment in result.get("segments", []):
        for word in segment.get("words", []):
            text = word.get("word", "").strip()
            # Split grouped tokens Whisper may emit (e.g. "you know" as one entry)
            for subtext in text.split():
                all_words.append({
                    "word": subtext,
                    "start": word.get("start", 0),
                    "end": word.get("end", 0),
                })

    transcript = result.get("text", "").strip()
    audio_duration = get_audio_duration(filepath)
    issues, detected_fillers, pauses, stutters, fast_phrases = analyze_fluency(all_words, transcript, audio_duration)
    
    return {
        "transcript": transcript,
        "issues": issues,
        "fillers": detected_fillers,
        "pauses": pauses,
        "stutters": stutters,
        "fast": fast_phrases,
        "all_words": all_words
    }

def test_perfect_speech():
    res = run_analysis("perfect_speech.m4a")
    assert len(res["issues"]) == 0, f"Expected 0 issues, got {res['issues']}"

def test_soft_fillers():
    res = run_analysis("soft_fillers.m4a")
    assert len(res["fillers"]) > 0, "Expected soft fillers but detected none."

def test_hard_fillers():
    res = run_analysis("hard_fillers.m4a")
    assert len(res["fillers"]) > 0, "Expected hard ugh/um fillers but detected none."

def test_stuttering():
    res = run_analysis("stuttering.m4a")
    assert len(res["stutters"]) > 0, "Expected stuttering but detected none."

def test_long_pauses():
    res = run_analysis("long_pauses.m4a")
    print(f"\n[DEBUG] test_long_pauses word timestamps: {res['all_words']}")
    assert len(res["pauses"]) > 0, "Expected pauses but detected none."

def test_fast_speech():
    res = run_analysis("fast_speech.m4a")
    assert len(res["fast"]) > 0, "Expected fast phrases but detected none."

def test_slow_speech():
    res = run_analysis("slow_speech.m4a")
    print(f"\n[DEBUG] test_slow_speech raw data: {res}")
    # Slow speech usually gets flagged as minor/major hesitations between words 
    # if pauses > 0.5s or via wpm calculation if added.
    # We will verify it triggers at least one hesitation/pause related issue.
    pause_issues = [i for i in res["issues"] if "HESITATION" in i["title"] or "PAUSE" in i["title"]]
    assert len(pause_issues) > 0 or len(res["pauses"]) > 0, "Expected slow speech/hesitations but detected none."

def test_comprehensive_all_issues():
    res = run_analysis("comprehensive_test.m4a")
    print(f"\n[DEBUG] test_comprehensive raw data: {res}")
    # This should trigger multiple categories
    assert len(res["fillers"]) > 0, "Expected fillers in comprehensive test."
    assert len(res["pauses"]) > 0, "Expected pauses in comprehensive test."
    assert len(res["stutters"]) > 0, "Expected stutters in comprehensive test."
    # We might not explicitly hit 'fast' if the speaker mixes speeds, but we expect multiple issues
    assert len(res["issues"]) >= 3, f"Expected at least 3 distinct issues in comprehensive test, got {len(res['issues'])}"
