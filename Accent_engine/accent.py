from pydub import AudioSegment
from TTS.api import TTS

tts = TTS(model_name="tts_models/multilingual/multi-dataset/xtts_v2", gpu=False)

text = """
Welcome to Lingua Franca, your personal English learning companion.
Today we will be practicing spoken English together.
English is one of the most widely spoken languages in the world,
and mastering it can open many doors for you personally and professionally.
Let us start with some basic conversation skills.
Remember, the key to improving your English is consistent practice every single day.
Do not be afraid to make mistakes, because mistakes are how we learn and grow.
Keep going, and you will see great improvement over time.
"""

# American English
tts.tts_to_file(
    text=text,
    speaker_wav=r"C:\Users\hp\Downloads\english18.wav",
    language="en",
    file_path="output_american.wav"
)
print("Done! American accent saved to output_american.wav")

# British English
tts.tts_to_file(
    text=text,
    speaker_wav=r"C:\Users\hp\Downloads\english188.wav",
    language="en",
    file_path="output_british.wav"
)
print("Done! British accent saved to output_british.wav")

# Pakistani English
tts.tts_to_file(
    text=text,
    speaker_wav=r"C:\Users\hp\Downloads\audio.wav",
    language="en",
    file_path="output_pakistani.wav"
)
print("Done! Pakistani accent saved to output_pakistani.wav")