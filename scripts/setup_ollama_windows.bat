@echo off
echo Lingua Franca - Local AI Setup (Windows)
echo ----------------------------------------

:: Check if ollama is installed
where ollama >nul 2>nul
if %errorlevel% neq 0 (
    echo Ollama could not be found. 
    echo Please download and install Ollama from https://ollama.com/download/windows
    echo After installing, please run this script again.
    pause
    exit /b
)

echo Make sure the Ollama application is running.

echo.
echo Pulling llama3.2 (3B) model (this is highly recommended for 8GB RAM devices)...
ollama pull llama3.2

echo.
echo --- PHYSICAL ANDROID DEVICE SETUP ---
echo To test on a physical Android device, you have two options:
echo.
echo OPTION 1: ADB Reverse (USB Tethering)
where adb >nul 2>nul
if %errorlevel% equ 0 (
    echo ADB is installed. Attempting to set up reverse port forwarding...
    adb reverse tcp:11434 tcp:11434
    if %errorlevel% equ 0 (
        echo ADB reverse port forwarding successful! Keep OLLAMA_URL=http://127.0.0.1:11434/api/chat in your .env file.
    ) else (
        echo ADB reverse failed. Make sure your device is connected via USB.
    )
) else (
    echo ADB could not be found in your PATH. 
)
echo.
echo OPTION 2: Wi-Fi LAN Connection (More Stable)
echo Setting Ollama to accept local network connections...
setx OLLAMA_HOST "0.0.0.0" >nul 2>nul
if %errorlevel% equ 0 (
    echo [SUCCESS] OLLAMA_HOST set. You must RESTART the Ollama app for this to take effect!
    echo.
    echo To use Wi-Fi:
    echo 1. Open Command Prompt and type: ipconfig
    echo 2. Find your "IPv4 Address" (e.g., 192.168.1.X)
    echo 3. In the Flutter project's .env file, add/update this line:
    echo    OLLAMA_URL=http://YOUR_IPv4_ADDRESS:11434/api/chat
) else (
    echo Could not set OLLAMA_HOST automatically. Run 'setx OLLAMA_HOST "0.0.0.0"' manually.
)
echo -------------------------------------
echo.

echo Setup complete! The local AI is ready for use.
pause
