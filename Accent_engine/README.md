# Accent Engine Setup (Mac & Windows)

This guide provides instructions to set up the Accent Engine locally. Since the TTS Engine has a few specific dependency version requirements, it is highly recommended to follow these instructions closely.

## Prerequisites
- Python 3.10 (Specifically `3.10`, as newer versions like `3.13` have missing modules or compatibility issues)
- FFmpeg installed (for audio processing).

## Setup (macOS / Linux)

### 1. Download/Install Python 3.10
If you don't have Python 3.10 explicitly installed, you can use Homebrew:
```bash
brew install python@3.10
```

### 2. Create the Virtual Environment & Install Dependencies
Open your terminal and navigate to the `Accent_engine` directory:
```bash
cd path/to/FYP-Project/Accent_engine

# Remove any existing venv if present
rm -rf venv 

# Create virtual environment using exactly python3.10
python3.10 -m venv venv
source venv/bin/activate

# Upgrade pip and install the initial requirements
pip install --upgrade pip
pip install -r requirements.txt
```

### 3. Fix Dependency Conflicts (CRITICAL)
Due to a few compatibility issues with recent library updates, you **MUST** run the following downgrade commands to patch the environment:
```bash
# 1. Downgrade setuptools (fixes "ModuleNotFoundError: pkg_resources")
pip install "setuptools<70.0.0"

# 2. Downgrade transformers (fixes "ImportError: BeamSearchScorer")
pip install transformers==4.36.0

# 3. Downgrade torch and torchaudio (fixes PyTorch 2.6 weights_only security block)
pip install "torch<2.6" "torchaudio<2.6" --index-url https://download.pytorch.org/whl/cpu
```

### 4. Run the Server
While inside the `venv` virtual environment, you can now start the text-to-speech FastAPI backend:
```bash
uvicorn tts_service:app --host 0.0.0.0 --port 8000
```
*Note: The first time you run this, it will download a ~1.87GB model (`xtts_v2`), which will take a few minutes.*

### 5. ADB Reverse (for Android Emulator connection)
To allow the Flutter Android application to communicate with your Mac/PC's localhost (127.0.0.1:8000), open a *second terminal* and run:
```bash
~/Library/Android/sdk/platform-tools/adb reverse tcp:8000 tcp:8000
```


---

## Setup (Windows)

1. **Verify Python Version**: Ensure you have Python 3.10 installed.

2. **Open PowerShell** and Navigate to the project:
   ```powershell
   cd "path\to\FYP-Project\Accent_engine"
   ```
3. **Setup Environment**:
   ```powershell
   python -m venv venv
   & "venv\Scripts\Activate.ps1"
   pip install --upgrade pip
   pip install -r requirements.txt
   
   # Run the crucial downgrade commands to fix crashes
   pip install "setuptools<70.0.0" transformers==4.36.0 "torch<2.6" "torchaudio<2.6" --index-url https://download.pytorch.org/whl/cpu
   ```
4. **Run the Server**:
   ```powershell
   uvicorn tts_service:app --host 0.0.0.0 --port 8000
   ```
   ```powershell
   ~\AppData\Local\Android\Sdk\platform-tools\adb.exe reverse tcp:8000 tcp:8000
   ```

---

## Troubleshooting

### Issue 1: `Connection closed before full header was received` (STT freezing/error)
This means the Flutter app can reach the `adb reverse` tunnel, but the TTS FastAPI server is **not running** or has crashed.

**Fix:**
1. Open a terminal in the `Accent_engine` directory.
2. Activate the virtual environment: `source venv/bin/activate` (Mac) or `& "venv\Scripts\Activate.ps1"` (Windows).
3. Start the server (see Step 4 above): `uvicorn tts_service:app --host 0.0.0.0 --port 8000`

### Issue 2: `pip install` hanging for hours (especially `torchaudio`)
Sometimes the PyTorch CPU wheels get stuck downloading.

**Fix:**
1. Stop the hung process by pressing `Ctrl + C` in the python terminal.
2. Manually install it again using the PyTorch CPU index:
   ```bash
   pip install "torch<2.6" "torchaudio<2.6" --index-url https://download.pytorch.org/whl/cpu
   ```
3. To verify the installation succeeded, run:
   ```bash
   python -c "import TTS; print('TTS OK')"
   python -c "import torchaudio; print('torchaudio OK')"
   ```
   If both commands print "OK", the dependencies are fully installed and you can run the server.
