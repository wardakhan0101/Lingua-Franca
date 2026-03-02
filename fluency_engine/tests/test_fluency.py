import os
import sys
import pytest

# Add the parent directory to sys.path to import api.py
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from api import analyze_fluency, transcribe_audio

AUDIO_DIR = os.path.join(os.path.dirname(__file__), 'audio')

def run_analysis(filename):
    """Helper to run the full pipeline on a local audio file."""
    filepath = os.path.join(AUDIO_DIR, filename)
    if not os.path.exists(filepath):
        pytest.skip(f"Audio file {filename} not found.")
    
    transcript, words = transcribe_audio(filepath)
    issues, detected_fillers, pauses, stutters, fast_phrases = analyze_fluency(words, transcript)
    
    return {
        "transcript": transcript,
        "issues": issues,
        "fillers": detected_fillers,
        "pauses": pauses,
        "stutters": stutters,
        "fast": fast_phrases
    }

def test_perfect_speech():
    res = run_analysis("perfect_speech.wav")
    assert len(res["issues"]) == 0, f"Expected 0 issues, got {res['issues']}"

def test_soft_fillers():
    res = run_analysis("soft_fillers.wav")
    assert len(res["fillers"]) > 0, "Expected soft fillers but detected none."

def test_hard_fillers():
    res = run_analysis("hard_fillers.wav")
    assert len(res["fillers"]) > 0, "Expected hard ugh/um fillers but detected none."

def test_stuttering():
    res = run_analysis("stuttering.wav")
    assert len(res["stutters"]) > 0, "Expected stuttering but detected none."

def test_long_pauses():
    res = run_analysis("long_pauses.wav")
    assert len(res["pauses"]) > 0, "Expected pauses but detected none."

def test_fast_speech():
    res = run_analysis("fast_speech.wav")
    assert len(res["fast"]) > 0, "Expected fast phrases but detected none."

def test_slow_speech():
    res = run_analysis("slow_speech.wav")
    # Slow speech usually gets flagged as minor/major hesitations between words 
    # if pauses > 0.5s or via wpm calculation if added.
    # We will verify it triggers at least one hesitation/pause related issue.
    pause_issues = [i for i in res["issues"] if "HESITATION" in i["title"] or "PAUSE" in i["title"]]
    assert len(pause_issues) > 0 or len(res["pauses"]) > 0, "Expected slow speech/hesitations but detected none."

def test_comprehensive_all_issues():
    res = run_analysis("comprehensive_test.wav")
    # This should trigger multiple categories
    assert len(res["fillers"]) > 0, "Expected fillers in comprehensive test."
    assert len(res["pauses"]) > 0, "Expected pauses in comprehensive test."
    assert len(res["stutters"]) > 0, "Expected stutters in comprehensive test."
    # We might not explicitly hit 'fast' if the speaker mixes speeds, but we expect multiple issues
    assert len(res["issues"]) >= 3, f"Expected at least 3 distinct issues in comprehensive test, got {len(res['issues'])}"
