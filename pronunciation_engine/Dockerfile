FROM python:3.11-slim

RUN apt-get update && apt-get install -y \
    espeak-ng \
    ffmpeg \
    libsndfile1 \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

ENV HF_HOME=/app/models
ENV TRANSFORMERS_CACHE=/app/models

COPY download_models.py .
RUN python download_models.py

COPY *.py ./

# Cloud Run injects $PORT (typically 8080). Fall back to 8001 for local docker.
ENV PORT=8001
EXPOSE 8001
CMD exec uvicorn api:app --host 0.0.0.0 --port ${PORT}
