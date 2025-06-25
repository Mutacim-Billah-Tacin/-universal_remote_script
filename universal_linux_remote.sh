#!/bin/bash
set -euo pipefail

USERNAME=$(logname)
USERHOME=$(eval echo "~$USERNAME")

# === Config ===
BOT_TOKEN="8031708120:AAGT8n-dYqjtrLKaKIxJ8DEY1xoitg0R_U8"
CHAT_ID="5679829837"
LOCALTUNNEL_PORT=5900
LOCALTUNNEL_LOG="$USERHOME/localtunnel.log"

# === Package Manager Detection ===
if command -v apt &>/dev/null; then
  PKG="sudo apt install -y"
  UPDATE="sudo apt update"
  DISTRO="debian"
elif command -v dnf &>/dev/null; then
  PKG="sudo dnf install -y"
  UPDATE="sudo dnf check-update || true"
  DISTRO="fedora"
elif command -v yay &>/dev/null; then
  PKG="yay -S --noconfirm"
  UPDATE="echo skipping"
  DISTRO="arch"
elif command -v paru &>/dev/null; then
  PKG="paru -S --noconfirm"
  UPDATE="echo skipping"
  DISTRO="arch"
else
  echo "❌ No supported package manager found."
  exit 1
fi

echo "🧪 Detected distro: $DISTRO"

echo "📦 Installing packages..."
eval "$UPDATE"
eval "$PKG openssh-server x11vnc autocutsel"

echo "🛠️ Enabling SSH..."
sudo systemctl enable --now ssh || sudo systemctl enable --now sshd

# Firewall (Debian/Ubuntu)
if [[ "$DISTRO" == "debian" ]] && command -v ufw &>/dev/null; then
  echo "🛡️ Enabling UFW and allowing SSH"
  sudo ufw allow ssh
  sudo ufw --force enable
fi

echo "🔐 Setting VNC password..."
read -sp "Enter VNC password: " vncpass
echo
sudo -u "$USERNAME" mkdir -p "$USERHOME/.vnc"
sudo -u "$USERNAME" x11vnc -storepasswd "$vncpass" "$USERHOME/.vnc/passwd"

echo "🧱 Creating x11vnc systemd service..."
sudo tee /etc/systemd/system/x11vnc.service > /dev/null <<EOF
[Unit]
Description=Start x11vnc at boot (real desktop sharing)
After=graphical.target
Requires=graphical.target

[Service]
Type=simple
Environment=DISPLAY=:0
ExecStartPre=/bin/sleep 10
ExecStart=/bin/bash -c 'autocutsel -fork && /usr/bin/x11vnc -display :0 -auth $USERHOME/.Xauthority -rfbauth $USERHOME/.vnc/passwd -forever -loop -noxdamage -repeat -shared -localhost'
User=$USERNAME
Group=$USERNAME
Restart=always

[Install]
WantedBy=graphical.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now x11vnc

# === LocalTunnel Setup ===
if ! command -v npx &>/dev/null; then
  echo "📦 Installing Node.js (required for LocalTunnel)..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  eval "$PKG nodejs"
fi

echo "🌐 Starting LocalTunnel..."
sudo -u "$USERNAME" pkill -f "lt --port" || true
sudo -u "$USERNAME" nohup npx localtunnel --port $LOCALTUNNEL_PORT > "$LOCALTUNNEL_LOG" 2>&1 &

sleep 5  # wait for LT to boot up

TUNNEL_URL=$(grep -oP '(https://[a-zA-Z0-9\.-]+\.loca\.lt)' "$LOCALTUNNEL_LOG" | tail -1)

# === Telegram Notification ===
if [[ -n "$TUNNEL_URL" ]]; then
  echo "📩 Sending tunnel to Telegram..."
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d text="📡 *Remote Tunnel Ready!*\n\nUser: \`$USERNAME\`\nTunnel: [$TUNNEL_URL]($TUNNEL_URL)" \
    -d parse_mode="Markdown"
else
  echo "⚠️ LocalTunnel failed to start."
fi

echo "✅ DONE! SSH and VNC are ready."
echo "You can connect using:"
echo "  ssh -L 5900:localhost:5900 $USERNAME@<IP>"
echo "  vncviewer localhost:5900"
