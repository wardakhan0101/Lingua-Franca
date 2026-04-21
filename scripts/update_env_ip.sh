#!/usr/bin/env bash
# scripts/update_env_ip.sh
#
# Detects this Mac's current LAN IP and writes it into OLLAMA_URL in .env so a
# physical Android device on the same Wi-Fi can reach Ollama. Run this any time
# your laptop's IP changes (new Wi-Fi, lease renewal, etc).
#
# Usage (from project root OR scripts/):
#   ./scripts/update_env_ip.sh
#
# Recommended: wire this in as a pre-launch step in Android Studio's Flutter
# run configuration, or just alias `flutter run` to call it first.

set -e
cd "$(dirname "$0")/.."

ENV_FILE=".env"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: $ENV_FILE not found in $(pwd)." >&2
  exit 1
fi

# First non-loopback IPv4 on any active interface.
LAN_IP=$(ifconfig | awk '/^[a-z0-9]+: / {iface=$1} /inet / && $2 !~ /^127\./ && iface!=""{print $2; exit}')

if [ -z "$LAN_IP" ]; then
  echo "ERROR: Could not detect a LAN IP. Are you connected to Wi-Fi or Ethernet?" >&2
  exit 1
fi

NEW_URL="http://${LAN_IP}:11434/api/chat"

if grep -q "^OLLAMA_URL=" "$ENV_FILE"; then
  # BSD sed needs the '' after -i on macOS.
  sed -i '' "s|^OLLAMA_URL=.*|OLLAMA_URL=${NEW_URL}|" "$ENV_FILE"
else
  echo "OLLAMA_URL=${NEW_URL}" >> "$ENV_FILE"
fi

echo "[OK] .env: OLLAMA_URL=${NEW_URL}"

# Make sure Ollama is listening on all interfaces.
CURRENT_HOST=$(launchctl getenv OLLAMA_HOST 2>/dev/null || true)
if [ "$CURRENT_HOST" != "0.0.0.0" ]; then
  echo "[WARN] OLLAMA_HOST is '${CURRENT_HOST:-unset}'. Setting to 0.0.0.0..."
  launchctl setenv OLLAMA_HOST "0.0.0.0"
  echo "       Quit AND relaunch the Ollama menubar app now for this to take effect."
fi

echo ""
echo "Done. Fully stop+restart Flutter to pick up the new .env (hot reload won't)."
