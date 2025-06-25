#!/bin/bash
set -euo pipefail

USERNAME=$(logname)
USERHOME=$(eval echo "~$USERNAME")

# === Config ===
BOT_TOKEN="7521307374:AAFdxe5wBLHwY7y-OQ5vvJ3wY0sI-YhZBXw"   # Replace with your token
CHAT_ID="5679829837"                                       # Replace with your chat ID
LOCALTUNNEL_PORT=5900
LOCALTUNNEL_LOG="$USERHOME/localtunnel.log"
MAX_LT_RETRIES=3

# --- Detect session type ---
SESSION_TYPE="${XDG_SESSION_TYPE:-}"

if [[ "$SESSION_TYPE" == "wayland" ]]; then
  echo "⚠️ Wayland detected, switching to X11..."

  if [[ -f /etc/gdm/custom.conf ]]; then
    sudo sed -i 's/^#WaylandEnable=false/WaylandEnable=false/' /etc/gdm/custom.conf || true
    if ! grep -q "^WaylandEnable=false" /etc/gdm/custom.conf; then
      echo "WaylandEnable=false" | sudo tee -a /etc/gdm/custom.conf > /dev/null
    fi

    echo "✅ GDM config updated to disable Wayland."
    echo "🔄 Rebooting system to apply X11 session..."
    sudo reboot
  else
    echo "❌ /etc/gdm/custom.conf not found! Cannot auto-switch Wayland to X11."
    echo "Please manually disable Wayland in your display manager."
    exit 1
  fi
fi

# --- Detect Distro ---
if command -v apt &>/dev/null; then
  PKG_INSTALL="sudo apt install -y"
  PKG_UPDATE="sudo apt update"
  DISTRO="debian"
elif command -v dnf &>/dev/null; then
  PKG_INSTALL="sudo dnf install -y"
  PKG_UPDATE="sudo dnf check-update || true"
  DISTRO="fedora"
elif command -v pacman &>/dev/null; then
  PKG_INSTALL="sudo pacman -S --noconfirm"
  PKG_UPDATE="sudo pacman -Sy"
  DISTRO="arch"
else
  echo "❌ Unsupported Linux distro."
  exit 1
fi

echo "🧪 Detected distro: $DISTRO"
echo "📦 Updating package list..."
eval "$PKG_UPDATE"

echo "📦 Installing dependencies..."
if [[ "$DISTRO" == "arch" ]]; then
  eval "$PKG_INSTALL openssh x11vnc autocutsel nodejs npm"
else
  eval "$PKG_INSTALL openssh-server x11vnc autocutsel nodejs npm"
fi

# Enable SSH service
if systemctl list-unit-files | grep -q '^ssh.service'; then
  sudo systemctl enable --now ssh.service
elif systemctl list-unit-files | grep -q '^sshd.service'; then
  sudo systemctl enable --now sshd.service
else
  echo "⚠️ SSH service not found. Please start SSH manually."
fi

# Firewall (Debian ufw, Fedora firewalld)
if [[ "$DISTRO" == "debian" ]] && command -v ufw &>/dev/null; then
  sudo ufw allow ssh
  sudo ufw allow 5900/tcp
  sudo ufw --force enable
elif [[ "$DISTRO" == "fedora" ]] && command -v firewall-cmd &>/dev/null; then
  sudo firewall-cmd --add-service=ssh --permanent
  sudo firewall-cmd --add-port=5900/tcp --permanent
  sudo firewall-cmd --reload
fi

# VNC password setup
echo "🔐 Set VNC password:"
read -sp "Password (8+ chars): " VNC_PASS
echo
sudo -u "$USERNAME" mkdir -p "$USERHOME/.vnc"
sudo -u "$USERNAME" x11vnc -storepasswd "$VNC_PASS" "$USERHOME/.vnc/passwd"

# Create x11vnc systemd service
DISPLAY_NUM=":0"
XAUTH_FILE="$USERHOME/.Xauthority"

sudo tee /etc/systemd/system/x11vnc.service > /dev/null <<EOF
[Unit]
Description=x11vnc server
After=graphical.target
Requires=graphical.target

[Service]
Type=simple
Environment=DISPLAY=$DISPLAY_NUM
ExecStartPre=/bin/sleep 10
ExecStart=/usr/bin/x11vnc -display $DISPLAY_NUM -auth $XAUTH_FILE -rfbauth $USERHOME/.vnc/passwd -forever -loop -noxdamage -repeat -shared -localhost
User=$USERNAME
Group=$USERNAME
Restart=always
RestartSec=5

[Install]
WantedBy=graphical.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now x11vnc.service

# Start autocutsel for clipboard sharing
pkill autocutsel || true
sudo -u "$USERNAME" autocutsel -fork &

# Start LocalTunnel with retries
pkill -f "lt --port $LOCALTUNNEL_PORT" || true

retry=0
TUNNEL_URL=""

while [[ $retry -lt $MAX_LT_RETRIES ]]; do
  sudo -u "$USERNAME" nohup npx localtunnel --port $LOCALTUNNEL_PORT > "$LOCALTUNNEL_LOG" 2>&1 &
  sleep 6
  TUNNEL_URL=$(grep -oP '(https://[a-zA-Z0-9\.-]+\.loca\.lt)' "$LOCALTUNNEL_LOG" | tail -1 || true)
  
  if [[ -n "$TUNNEL_URL" ]]; then
    echo "✅ LocalTunnel started: $TUNNEL_URL"
    break
  else
    echo "⚠️ LocalTunnel failed, retrying ($((retry + 1))/$MAX_LT_RETRIES)..."
    ((retry++))
    pkill -f "lt --port $LOCALTUNNEL_PORT" || true
    sleep 3
  fi
done

# Telegram notification
if [[ -n "$TUNNEL_URL" ]]; then
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d text="📡 *Remote Tunnel Ready!*\n\nUser: \`$USERNAME\`\nTunnel: [$TUNNEL_URL]($TUNNEL_URL)" \
    -d parse_mode="Markdown"
else
  echo "⚠️ Failed to start LocalTunnel. Telegram notification skipped."
fi

echo "✅ Linux remote setup complete!"
echo "Connect with:"
echo "  ssh -L 5900:localhost:5900 $USERNAME@<IP>"
echo "  vncviewer localhost:5900"
echo "⚠️ Reminder: VNC over public tunnels is insecure; use SSH tunnels or VPNs for sensitive tasks."
