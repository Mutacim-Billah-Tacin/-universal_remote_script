#!/bin/bash
set -euo pipefail

USERNAME=$(logname)
USERHOME=$(eval echo "~$USERNAME")

# === Config ===
LOCALTUNNEL_PORT=5900       # VNC port
VNC_PASS_FILE="$USERHOME/.vnc/passwd"
SERVICE_X11VNC="/etc/systemd/system/x11vnc.service"
SERVICE_CF="/etc/systemd/system/cloudflared.service"

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
eval "$PKG openssh-server x11vnc autocutsel curl"

# Enable SSH
sudo systemctl enable --now ssh || sudo systemctl enable --now sshd

# === VNC Setup ===
echo "🔐 Setting VNC password..."
read -sp "Enter VNC password: " vncpass
echo
sudo -u "$USERNAME" mkdir -p "$USERHOME/.vnc"
sudo -u "$USERNAME" x11vnc -storepasswd "$vncpass" "$VNC_PASS_FILE"

# Create x11vnc systemd service
sudo tee "$SERVICE_X11VNC" > /dev/null <<EOF
[Unit]
Description=Start x11vnc at boot
After=graphical.target
Requires=graphical.target

[Service]
Type=simple
Environment=DISPLAY=:0
ExecStartPre=/bin/sleep 10
ExecStart=/bin/bash -c 'autocutsel -fork && /usr/bin/x11vnc -display :0 -auth %h/.Xauthority -rfbauth %h/.vnc/passwd -forever -loop -noxdamage -repeat -shared -localhost'
User=$USERNAME
Group=$USERNAME
Restart=always

[Install]
WantedBy=graphical.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now x11vnc

# === Cloudflared Tunnel Setup ===
if ! command -v cloudflared &>/dev/null; then
  echo "📦 Installing Cloudflared..."
  if [[ "$DISTRO" == "arch" ]]; then
    eval "$PKG cloudflared"
  else
    curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o cloudflared.deb
    sudo apt install ./cloudflared.deb -y || true
  fi
fi

echo "🌐 Setting up persistent Cloudflare Tunnel..."

# Create systemd service for automatic tunnel
sudo tee "$SERVICE_CF" > /dev/null <<EOF
[Unit]
Description=Cloudflare Tunnel for SSH & VNC
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/cloudflared tunnel --url ssh://localhost:22 --url vnc://localhost:5900
Restart=always
User=$USERNAME

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now cloudflared

# Wait a few seconds for the tunnel to start
sleep 5

# Fetch public URLs automatically
echo "⌛ Waiting for Cloudflare Tunnel to assign public URLs..."
PUBLIC_URLS=$(cloudflared tunnel list | awk '/ACTIVE/ {print $2}')

if [[ -z "$PUBLIC_URLS" ]]; then
  echo "⚠️ Could not detect public URL automatically. Check with:"
  echo "  journalctl -u cloudflared -f"
else
  echo "✅ DONE! Your machine is now accessible via Cloudflare Tunnel:"
  echo "  SSH: ssh $USERNAME@$PUBLIC_URLS"
  echo "  VNC: $PUBLIC_URLS:5900"
fi
