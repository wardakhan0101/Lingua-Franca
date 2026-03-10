# Running Local AI (Ollama) on Physical Android Devices

It's common to see a `Network Error` when testing the app on a physical Android device. This happens because the Android device cannot reach your Mac/Windows `localhost` over the network by default.

Here is a step-by-step guide to fixing the network error, broken down into two options depending on how you prefer to connect.

---

## Option 1: Wi-Fi LAN Connection (Recommended & Most Reliable)
By default, the Ollama app only listens to requests coming from the *exact same computer*. To access the AI from your physical phone over Wi-Fi, you must explicitly allow local network traffic and point the phone to your computer's IP address.

### Step 1: Tell Ollama to accept network connections
**On Mac:**
1. Open your terminal.
2. Run this command to set the environment variable:
   ```bash
   launchctl setenv OLLAMA_HOST "0.0.0.0"
   ```
3. **CRITICAL:** You must completely quit and restart the Ollama app (click the llama icon in your top-right menu bar and select "Quit", then open it again from your Applications folder).

**On Windows:**
1. Open Command Prompt as Administrator.
2. Run this command:
   ```cmd
   setx OLLAMA_HOST "0.0.0.0"
   ```
3. **CRITICAL:** You must completely quit and restart the Ollama app (right-click the llama icon in your bottom-right system tray and select "Quit", then open it again from the Start menu).

### Step 2: Find your Computer's Local IP Address
**On Mac:**
1. Open terminal and run:
   ```bash
   ifconfig | grep "inet " | grep -v 127.0.0.1
   ```
2. Look for the IP address (e.g., `192.168.18.61`).

**On Windows:**
1. Open Command Prompt and run:
   ```cmd
   ipconfig
   ```
2. Look for the "IPv4 Address" (e.g., `192.168.1.X`).

### Step 3: Update the `.env` file
1. Open the `.env` file in the root of your Flutter project.
2. Update the `OLLAMA_URL` line to match your exact IP address from Step 2:
   ```env
   # Example: If your IP is 192.168.18.61, it should look exactly like this:
   OLLAMA_URL=http://192.168.18.61:11434/api/chat
   ```
3. **CRITICAL:** Because you changed the `.env` file, you must **fully stop and restart the Flutter app**. A "hot reload" or "hot restart" will not load the new IP address.

---

## Option 2: USB Cable & ADB Reverse Port Forwarding (Less Reliable)
If you do not want to change your IP address on Wi-Fi (because laptops frequently change IP addresses when moving), you can use a direct USB cable and Android Debug Bridge (ADB). 

*Note: Android will frequently drop this connection if using Wireless ADB.*

1. Connect your Android phone directly via a USB cable.
2. Leave `OLLAMA_URL=http://127.0.0.1:11434/api/chat` in your `.env` file.
3. Open a terminal inside Android Studio (or VS Code) and run this exact command:
   ```bash
   adb reverse tcp:11434 tcp:11434
   ```
4. If the command succeeds, it will open a "tunnel" connecting the phone's localhost directly to the computer's localhost.
5. If you unplug the phone, lock the screen for too long, or the connection breaks, you will get a Network Error again and **must run the `adb reverse` command again**.

---

## Quick Troubleshooting Checklist
Still getting a Network Error? 
- [ ] Is the Ollama app *actually running*? (Look for the tray icon).
- [ ] Did you pull the correct model size? (`ollama pull llama3.2`)
- [ ] If using Wi-Fi (Option 1), did you completely restart the Ollama app after setting the `OLLAMA_HOST` variable?
- [ ] If using Wi-Fi (Option 1), did your computer's IP address change today? Run `ifconfig` or `ipconfig` to verify.
- [ ] If using ADB (Option 2), did you unplug the phone or let it sleep? Run `adb reverse tcp:11434 tcp:11434` again.
