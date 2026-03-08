FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    gcc \
    g++ \
    openjdk-21-jre-headless \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Download spaCy model
RUN pip install https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.7.1/en_core_web_sm-3.7.1-py3-none-any.whl

# PRE-DOWNLOAD LanguageTool to avoid startup timeout
RUN python -c "import language_tool_python; lt = language_tool_python.LanguageTool('en-US'); lt.close()"

# PRE-DOWNLOAD T5 model to avoid first request timeout
RUN python -c "from transformers import AutoTokenizer, AutoModelForSeq2SeqLM; AutoTokenizer.from_pretrained('vennify/t5-base-grammar-correction'); AutoModelForSeq2SeqLM.from_pretrained('vennify/t5-base-grammar-correction')"

# Copy application code
COPY python_api.py .

# Expose port
EXPOSE 8080

# Run with increased timeout settings
CMD exec uvicorn python_api:app --host 0.0.0.0 --port $PORT --timeout-keep-alive 300
