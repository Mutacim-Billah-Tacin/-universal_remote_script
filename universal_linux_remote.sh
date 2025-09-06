#!/bin/bash
set -euo pipefail

USERNAME=$(logname)
USERHOME=$(eval echo "~$USERNAME")

# === Config ===
# Your personal Telegram details and VNC settings.
BOT_TOKEN="7521307374:AAH03Mymm0R5V16ez832iTF_NPporPX7yBg"
CHAT_ID="5679829837"
LOCALTUNNEL_PORT=5900
LOCALTUNNEL_LOG="$USERHOME/localtunnel.log"
TELEGRAM_URL="https://api.telegram.org/bot$BOT_TOKEN/sendMessage"

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

# === LocalTunnel Setup as a Systemd Service ===
if ! command -v npx &>/dev/null; then
  echo "📦 Installing Node.js (required for LocalTunnel)..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  eval "$PKG nodejs"
fi

echo "🌐 Creating Localtunnel systemd service..."
sudo tee /etc/systemd/system/localtunnel.service > /dev/null <<EOF
[Unit]
Description=Localtunnel Client
After=network.target

[Service]
Type=simple
User=$USERNAME
Group=$USERNAME
ExecStart=/usr/bin/npx localtunnel --port 5900
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now localtunnel

echo "📩 Sending initial tunnel link to Telegram..."
sleep 5
TUNNEL_URL=$(grep -oP '(https://[a-zA-Z0-9\.-]+\.loca\.lt)' "$LOCALTUNNEL_LOG" | tail -1)
if [[ -n "$TUNNEL_URL" ]]; then
    curl -s -X POST "$TELEGRAM_URL" \
    -d chat_id="$CHAT_ID" \
    -d text="📡 *Remote Tunnel Ready!*\n\nUser: \`$USERNAME\`\nTunnel: [$TUNNEL_URL]($TUNNEL_URL)" \
    -d parse_mode="Markdown"
else
    echo "⚠️ LocalTunnel failed to start."
fi

echo "✅ DONE! SSH, VNC, and Localtunnel are now all set up to run automatically on boot."
echo "You can connect using:"
echo "  ssh -L 5900:localhost:5900 $USERNAME@<IP>"
echo "  vncviewer localhost:5900"
