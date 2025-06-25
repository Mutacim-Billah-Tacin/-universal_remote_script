# Requires running PowerShell as Admin

$BotToken = "7521307374:AAFdxe5wBLHwY7y-OQ5vvJ3wY0sI-YhZBXw" # Replace your token
$ChatID = "5679829837"                                     # Replace your chat ID
$LocalTunnelPort = 5900
$MaxRetries = 3
$TunnelUrl = $null

function Install-ChocoIfMissing {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Output "Chocolatey not found. Installing..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }
}

function Install-PackageIfMissing($package) {
    if (-not (Get-Package -Name $package -ErrorAction SilentlyContinue)) {
        choco install $package -y
    }
}

# Install Chocolatey if missing
Install-ChocoIfMissing

# Install OpenSSH Server if missing
if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) {
    Write-Output "Installing OpenSSH Server..."
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
}

Start-Service sshd
Set-Service sshd -StartupType Automatic

# Install TightVNC if missing
if (-not (Get-Command tvnserver.exe -ErrorAction SilentlyContinue)) {
    Write-Output "Installing TightVNC..."
    Install-PackageIfMissing "tightvnc"
}

# Prompt for VNC password
$VncPass = Read-Host -Prompt "Enter VNC password (8+ chars)" -AsSecureString
$Bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($VncPass)
$UnsecurePass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($Bstr)

# Configure TightVNC password (Registry)
$VncRegPath = "HKCU:\Software\TightVNC\Server"
if (-not (Test-Path $VncRegPath)) {
    New-Item -Path $VncRegPath -Force | Out-Null
}
Set-ItemProperty -Path $VncRegPath -Name "Password" -Value ([System.Text.Encoding]::ASCII.GetBytes($UnsecurePass))
Set-ItemProperty -Path $VncRegPath -Name "StartWithWindows" -Value 1

# Start TightVNC Server
Start-Process "C:\Program Files\TightVNC\tvnserver.exe"

# Install Node.js if missing
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Output "Installing Node.js..."
    Install-PackageIfMissing "nodejs"
}

# Start LocalTunnel with retries
function Start-LocalTunnel {
    param (
        [int]$port,
        [int]$retries
    )
    for ($i=0; $i -lt $retries; $i++) {
        Write-Output "Starting LocalTunnel attempt $($i + 1)..."
        $proc = Start-Process -FilePath "npx.cmd" -ArgumentList "localtunnel --port $port" -NoNewWindow -PassThru -RedirectStandardOutput "localtunnel.log"
        Start-Sleep -Seconds 6
        $log = Get-Content "localtunnel.log" -Raw
        if ($log -match '(https://[a-zA-Z0-9\.-]+\.loca\.lt)') {
            return $matches[0]
        }
        Stop-Process -Id $proc.Id -Force
        Start-Sleep -Seconds 3
    }
    return $null
}

$TunnelUrl = Start-LocalTunnel -port $LocalTunnelPort -retries $MaxRetries

if ($TunnelUrl) {
    Write-Output "LocalTunnel URL: $TunnelUrl"

    $Message = @{
        chat_id = $ChatID
        text = "📡 Remote Tunnel Ready!`nTunnel: $TunnelUrl"
    }

    Invoke-RestMethod -Uri "https://api.telegram.org/bot$BotToken/sendMessage" -Method Post -Body $Message
} else {
    Write-Output "Failed to start LocalTunnel."
}

Write-Output "✅ Windows remote setup complete!"
Write-Output "Connect with:"
Write-Output "  ssh -L 5900:localhost:5900 <username>@<IP>"
Write-Output "  Use TightVNC Viewer to connect to localhost:5900"
