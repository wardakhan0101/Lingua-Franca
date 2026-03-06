#!/bin/bash
# Setup script for Ollama on Mac

echo "Lingua Franca - Local AI Setup (Mac)"
echo "------------------------------------"

# Check if brew is installed
if ! command -v brew &> /dev/null
then
    echo "Homebrew could not be found. Please install Homebrew first from https://brew.sh/"
    exit 1
fi

# Check if ollama is installed
if ! command -v ollama &> /dev/null
then
    echo "Ollama could not be found. Installing via Homebrew..."
    brew install --cask ollama
else
    echo "Ollama is already installed."
fi

echo "Starting Ollama app..."
open -a Ollama

echo "Waiting for Ollama API to start..."
sleep 5

echo "Pulling llama3 model (this may take a while depending on your internet connection)..."
ollama pull llama3

echo "Setup complete! The local AI is ready for use."

echo ""
echo "--- PHYSICAL ANDROID DEVICE SETUP ---"
if command -v adb &> /dev/null
then
    echo "ADB is installed. Attempting to set up reverse port forwarding for physical devices..."
    if adb reverse tcp:11434 tcp:11434; then
        echo "ADB reverse port forwarding successful!"
    else
        echo "Could not set up ADB reverse port forwarding automatically. Make sure your device is connected and authorized."
    fi
else
    echo "ADB could not be found in your PATH."
    echo "If testing on a physical Android device, you MUST run this command in your Flutter project terminal:"
    echo "adb reverse tcp:11434 tcp:11434"
fi
echo "-------------------------------------"
echo ""
