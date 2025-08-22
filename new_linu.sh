#!/bin/bash
set -euo pipefail

USERNAME=$(logname)
USERHOME=$(eval echo "~$USERNAME")

# === Config ===
TUNNEL_NAME="mytunnel"
DOMAIN="mypc.example.com"   # <-- change this to your subdomain
LOCALTUNNEL_PORT=5900       # VNC port
VNC_PASS_FILE="$USERHOME/.vnc/passwd"
SERVICE_X11VNC="/etc/systemd/system/x11vnc.service"
SERVICE_CF="/etc/systemd/system/cloudflared.service"
CF_CONFIG="/etc/cloudflared/config.yml"

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

echo "🛠️ Enabling SSH..."
sudo systemctl enable --now ssh || sudo systemctl enable --now sshd

# === Firewall (Mint/Ubuntu/Debian only) ===
if [[ "$DISTRO" == "debian" ]] && command -v ufw &>/dev/null; then
  echo "🛡️ Enabling UFW and allowing SSH"
  sudo ufw allow ssh
  sudo ufw --force enable
fi

# === VNC Setup ===
echo "🔐 Setting VNC password..."
read -sp "Enter VNC password: " vncpass
echo
sudo -u "$USERNAME" mkdir -p "$USERHOME/.vnc"
sudo -u "$USERNAME" x11vnc -storepasswd "$vncpass" "$VNC_PASS_FILE"

echo "🧱 Creating x11vnc systemd service..."
sudo tee "$SERVICE_X11VNC" > /dev/null <<EOF
[Unit]
Description=Start x11vnc at boot (real desktop sharing)
After=graphical.target
Requires=graphical.target

[Service]
Type=simple
Environment=DISPLAY=:0
ExecStartPre=/bin/sleep 10
ExecStart=/bin/bash -c 'autocutsel -fork && /usr/bin/x11vnc -display :0 -auth $USERHOME/.Xauthority -rfbauth $VNC_PASS_FILE -forever -loop -noxdamage -repeat -shared -localhost'
User=$USERNAME
Group=$USERNAME
Restart=always

[Install]
WantedBy=graphical.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now x11vnc

# === Cloudflare Tunnel Setup ===
if ! command -v cloudflared &>/dev/null; then
  echo "📦 Installing Cloudflared..."
  curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o cloudflared.deb
  sudo apt install ./cloudflared.deb -y || true
fi

echo "🌐 Setting up Cloudflare Tunnel..."
echo "👉 NOTE: You need to run 'cloudflared tunnel login' ONCE manually and approve in the browser"
echo "    After that, re-run this script to configure the tunnel automatically."

if [[ -f /etc/cloudflared/cert.pem ]]; then
  sudo cloudflared tunnel create "$TUNNEL_NAME" || true
  sudo cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN"

  sudo tee "$CF_CONFIG" > /dev/null <<EOF
tunnel: $TUNNEL_NAME
credentials-file: /etc/cloudflared/${TUNNEL_NAME}.json

ingress:
  - hostname: $DOMAIN
    service: ssh://localhost:22
  - service: http_status:404
EOF

  sudo tee "$SERVICE_CF" > /dev/null <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/cloudflared tunnel --config $CF_CONFIG run
Restart=always
User=$USERNAME

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable --now cloudflared
  echo "✅ Cloudflare Tunnel is ready! Connect via: ssh $USERNAME@$DOMAIN"
else
  echo "⚠️ Skipping tunnel setup until you run 'cloudflared tunnel login' manually"
fi

echo "✅ DONE! SSH and VNC ready. Connect via:"
echo "  SSH: ssh $USERNAME@$DOMAIN"
echo "  VNC: $DOMAIN:5900"
