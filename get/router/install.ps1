# 360router Installer for Windows
# Usage: irm https://get.360ops.ai/router | iex
# ──────────────────────────────────────────────

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║         360router Installer           ║" -ForegroundColor Cyan
Write-Host "  ║   Smart AI Router - Local First       ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check Node.js
Write-Host "  [1/3] Checking Node.js..." -ForegroundColor Yellow
$nodeVersion = $null
try {
    $nodeVersion = (node --version 2>$null)
} catch {}

if (-not $nodeVersion) {
    Write-Host "  Node.js not found. Installing..." -ForegroundColor Red

    # Check if winget is available
    $hasWinget = Get-Command winget -ErrorAction SilentlyContinue

    if ($hasWinget) {
        Write-Host "  Installing Node.js via winget..." -ForegroundColor Yellow
        winget install OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements --silent

        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    } else {
        Write-Host ""
        Write-Host "  Please install Node.js 18+ from: https://nodejs.org" -ForegroundColor Red
        Write-Host "  Then re-run this installer." -ForegroundColor Red
        Write-Host ""
        exit 1
    }

    # Verify
    try {
        $nodeVersion = (node --version 2>$null)
    } catch {
        Write-Host "  Node.js installation failed. Please install manually from https://nodejs.org" -ForegroundColor Red
        exit 1
    }
}

$major = [int]($nodeVersion -replace 'v(\d+)\..*', '$1')
if ($major -lt 18) {
    Write-Host "  Node.js $nodeVersion found but v18+ required." -ForegroundColor Red
    Write-Host "  Please update: https://nodejs.org" -ForegroundColor Red
    exit 1
}
Write-Host "  Node.js $nodeVersion" -ForegroundColor Green

# Step 2: Install 360router
Write-Host "  [2/3] Installing 360router..." -ForegroundColor Yellow
npm install -g 360router 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Retrying with --force..." -ForegroundColor Yellow
    npm install -g 360router --force 2>$null
}

# Verify
$routerVersion = $null
try {
    $routerVersion = (360router --version 2>$null)
} catch {}

if (-not $routerVersion) {
    # Try npx as fallback
    Write-Host "  Trying npx fallback..." -ForegroundColor Yellow
    npx 360router --version 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Installation failed. Try manually: npm install -g 360router" -ForegroundColor Red
        exit 1
    }
}
Write-Host "  360router installed" -ForegroundColor Green

# Step 3: Launch setup wizard
Write-Host "  [3/3] Launching setup wizard..." -ForegroundColor Yellow
Write-Host ""
Write-Host "  ════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

360router init
