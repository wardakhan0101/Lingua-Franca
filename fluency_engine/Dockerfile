# Use official Python slim image
FROM python:3.11-slim

# Install ffmpeg (required by Whisper to decode audio formats)
RUN apt-get update && apt-get install -y ffmpeg git && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Install Python dependencies first (layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Pre-download the Whisper base model into the image
RUN python -c "import whisper; whisper.load_model('base')"

# Verify spaCy model is installed correctly
RUN python -c "import spacy; spacy.load('en_core_web_sm')"

# Copy app code
COPY api.py .

# Cloud Run expects the container to listen on port 8080
CMD ["uvicorn", "api:app", "--host", "0.0.0.0", "--port", "8080"]
