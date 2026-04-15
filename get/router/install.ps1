# 360router Installer for Windows — Binary distribution
# Usage: irm https://get.360ops.ai/router | iex
# ──────────────────────────────────────────────────
#
# Downloads the signed 360router binary from GitHub Releases.
# No Node.js required. No source code shipped.
# Existing configuration is preserved across upgrades.

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║         360Router Installer          ║" -ForegroundColor Cyan
Write-Host "  ║   Smart AI Router - Local First      ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$RELEASE_URL = "https://github.com/istninc/360ops-portal/releases/latest/download/360router-win.exe"
$INSTALL_DIR = "$env:LOCALAPPDATA\360Router"
$INSTALL_EXE = "$INSTALL_DIR\360router.exe"

# Detect existing install
$isUpgrade = Test-Path $INSTALL_EXE

# Detect existing config
$CONFIG_PATH = "$env:APPDATA\360router-nodejs\Config\config.json"
$hasConfig = Test-Path $CONFIG_PATH

# Step 1: Ensure install dir exists
Write-Host "  [1/3] Preparing install directory..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
Write-Host "  $INSTALL_DIR" -ForegroundColor Green

# Step 2: Download binary
Write-Host ""
if ($isUpgrade) {
    Write-Host "  [2/3] Upgrading 360router..." -ForegroundColor Yellow
} else {
    Write-Host "  [2/3] Downloading 360router..." -ForegroundColor Yellow
}

try {
    $ProgressPreference = 'Continue'
    Invoke-WebRequest -Uri $RELEASE_URL -OutFile $INSTALL_EXE -UseBasicParsing
} catch {
    Write-Host "  Download failed: $_" -ForegroundColor Red
    Write-Host "  URL: $RELEASE_URL" -ForegroundColor Red
    exit 1
}

Write-Host "  Downloaded $([math]::Round((Get-Item $INSTALL_EXE).Length / 1MB, 1)) MB" -ForegroundColor Green

# Step 3: Add to PATH
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*360Router*") {
    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$INSTALL_DIR", "User")
    # Update current session
    $env:PATH = "$env:PATH;$INSTALL_DIR"
    Write-Host "  Added to PATH" -ForegroundColor Green
}

# Step 4: Verify
$version = $null
try { $version = (& $INSTALL_EXE --version 2>$null) } catch {}

if (-not $version) {
    Write-Host "  Installation incomplete. Try: $INSTALL_EXE --version" -ForegroundColor Red
    exit 1
}
Write-Host "  360router v$version" -ForegroundColor Green

# Step 5: Configuration
Write-Host ""
Write-Host "  [3/3] Configuration..." -ForegroundColor Yellow

if ($hasConfig) {
    Write-Host "  Existing configuration detected — preserved." -ForegroundColor Green
    Write-Host ""
    Write-Host "  ════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Your API keys, providers, and preferences are intact." -ForegroundColor White
    Write-Host ""
    Write-Host "  To reconfigure:      360router init" -ForegroundColor Gray
    Write-Host "  To edit a setting:   360router config set" -ForegroundColor Gray
    Write-Host "  To start the proxy:  360router serve" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Restart your terminal if '360router' is not recognized." -ForegroundColor Gray
    Write-Host ""
    exit 0
}

# First-time install
Write-Host "  First-time install — launching setup wizard..." -ForegroundColor Yellow
Write-Host ""
Write-Host "  ════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

& $INSTALL_EXE init
