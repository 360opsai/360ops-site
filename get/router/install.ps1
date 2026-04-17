# 360router Installer for Windows — Binary distribution
# Usage: irm https://www.360ops.ai/get/router/install.ps1 | iex
# ──────────────────────────────────────────────────────────
#
# Downloads the 360router binary from GitHub Releases.
# No Node.js required. No source code shipped.
# Existing configuration is preserved across upgrades.

try {

Write-Host ""
Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║         360Router Installer          ║" -ForegroundColor Cyan
Write-Host "  ║   Smart AI Router - Local First      ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$RELEASE_URL = "https://github.com/istninc/360ops-releases/releases/download/360router-v2.4.0/360router-win.exe"
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
    Write-Host "  [2/3] Downloading 360router (~45 MB)..." -ForegroundColor Yellow
}

Write-Host "  Source: $RELEASE_URL" -ForegroundColor Gray
Write-Host ""

try {
    $ProgressPreference = 'Continue'
    Invoke-WebRequest -Uri $RELEASE_URL -OutFile $INSTALL_EXE -UseBasicParsing
} catch {
    Write-Host ""
    Write-Host "  ✗ Download failed." -ForegroundColor Red
    Write-Host "  Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Try downloading manually:" -ForegroundColor Yellow
    Write-Host "  $RELEASE_URL" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Save to: $INSTALL_EXE" -ForegroundColor Gray
    Write-Host ""
    Read-Host "  Press Enter to close"
    exit 1
}

$fileSize = [math]::Round((Get-Item $INSTALL_EXE).Length / 1MB, 1)
Write-Host "  Downloaded $fileSize MB" -ForegroundColor Green

# Step 3: Add to PATH
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*360Router*") {
    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$INSTALL_DIR", "User")
    $env:PATH = "$env:PATH;$INSTALL_DIR"
    Write-Host "  Added to PATH" -ForegroundColor Green
} else {
    Write-Host "  Already in PATH" -ForegroundColor Green
}

# Step 4: Verify
$version = $null
try { $version = (& $INSTALL_EXE --version 2>$null) } catch {}

if (-not $version) {
    Write-Host ""
    Write-Host "  ✗ Binary downloaded but failed to run." -ForegroundColor Red
    Write-Host "  File: $INSTALL_EXE" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Windows Defender may have blocked it." -ForegroundColor Yellow
    Write-Host "  Open Windows Security > Virus & Threat Protection > Protection History" -ForegroundColor Yellow
    Write-Host "  and allow 360router.exe if it was quarantined." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "  Press Enter to close"
    exit 1
}

Write-Host "  360router v$version ✓" -ForegroundColor Green

# Step 5: Configuration
Write-Host ""
Write-Host "  [3/3] Configuration..." -ForegroundColor Yellow

if ($hasConfig) {
    Write-Host "  Existing configuration detected — preserved." -ForegroundColor Green
    Write-Host ""
    Write-Host "  ════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  ✓ 360Router installed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Your API keys, providers, and preferences are intact." -ForegroundColor White
    Write-Host ""

    # Show status right here — no need to open new terminal
    Write-Host "  Checking providers..." -ForegroundColor Yellow
    Write-Host ""
    & $INSTALL_EXE status
    Write-Host ""
    Write-Host "  Ready to go:" -ForegroundColor Green
    Write-Host "    360router serve        Start the proxy" -ForegroundColor Cyan
    Write-Host "    360router config       View settings" -ForegroundColor Cyan
    Write-Host "    360router init         Reconfigure" -ForegroundColor Cyan
    Write-Host ""
    exit 0
}

# First-time install — run the wizard right here
Write-Host ""
Write-Host "  ════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  ✓ 360Router installed! Starting setup..." -ForegroundColor Green
Write-Host ""

& $INSTALL_EXE init

} catch {
    Write-Host ""
    Write-Host "  ═══ INSTALLER ERROR ═══" -ForegroundColor Red
    Write-Host ""
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  If this keeps happening, download manually:" -ForegroundColor Yellow
    Write-Host "  https://github.com/istninc/360ops-portal/releases" -ForegroundColor Cyan
    Write-Host ""
    Read-Host "  Press Enter to close"
}
