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
echo "To test on a physical Android device, you have two options:"
echo ""
echo "OPTION 1: ADB Reverse (USB Tethering)"
if command -v adb &> /dev/null
then
    echo "ADB is installed. Attempting to set up reverse port forwarding..."
    if adb reverse tcp:11434 tcp:11434; then
        echo "ADB reverse port forwarding successful! Keep OLLAMA_URL=http://127.0.0.1:11434/api/chat in your .env file."
    else
        echo "ADB reverse failed. Make sure your device is connected via USB."
    fi
else
    echo "ADB could not be found in your PATH."
fi

echo ""
echo "OPTION 2: Wi-Fi LAN Connection (More Stable)"
echo "Setting Ollama to accept local network connections..."
launchctl setenv OLLAMA_HOST "0.0.0.0"
echo "[SUCCESS] OLLAMA_HOST set. You must RESTART the Ollama app for this to take effect!"
echo ""
echo "To use Wi-Fi:"
echo "1. Find your Mac's IP address by running: ifconfig | grep 'inet ' | grep -v 127.0.0.1 | awk '{print \$2}'"
echo "2. In the Flutter project's .env file, add/update this line:"
echo "   OLLAMA_URL=http://YOUR_MAC_IP_ADDRESS:11434/api/chat"
echo "-------------------------------------"
echo ""
