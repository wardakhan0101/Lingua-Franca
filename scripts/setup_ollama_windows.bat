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
echo Pulling llama3 model (this may take a while depending on your internet connection)...
ollama pull llama3

echo.
echo --- PHYSICAL ANDROID DEVICE SETUP ---
where adb >nul 2>nul
if %errorlevel% equ 0 (
    echo ADB is installed. Attempting to set up reverse port forwarding for physical devices...
    adb reverse tcp:11434 tcp:11434
    if %errorlevel% equ 0 (
        echo ADB reverse port forwarding successful!
    ) else (
        echo Could not set up ADB reverse port forwarding automatically. Make sure your device is connected and authorized.
    )
) else (
    echo ADB could not be found in your PATH. 
    echo If testing on a physical Android device, you MUST run this command in your Flutter project terminal:
    echo adb reverse tcp:11434 tcp:11434
)
echo -------------------------------------
echo.

echo Setup complete! The local AI is ready for use.
pause
