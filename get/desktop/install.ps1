# 360ops Desktop Installer for Windows — Binary distribution
# Usage: irm https://www.360ops.ai/get/desktop/install.ps1 | iex
# (also works at: https://360ops-site-production.up.railway.app/get/desktop/install.ps1)
# ──────────────────────────────────────────────────────────────────
#
# Downloads the 360ops Desktop binary from the public 360ops-releases
# repo. No admin required — installs to %LOCALAPPDATA%, registers a
# Start Menu shortcut, and auto-starts on login.
#
# To uninstall: delete %LOCALAPPDATA%\Programs\360ops + Start Menu
# shortcut + the HKCU\...\Run key entry "360ops-Desktop".

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ─── Branding banner ───────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║       360ops Desktop Installer       ║" -ForegroundColor Cyan
Write-Host "  ║   Ambient AI Assistant — Windows     ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ─── Sanity checks ─────────────────────────────────────────────────
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "  PowerShell 5.0+ required." -ForegroundColor Red
    return
}
if ($IsLinux -or $IsMacOS) {
    Write-Host "  Windows only for now (macOS + Linux builds shipping soon)." -ForegroundColor Red
    return
}
$arch = (Get-CimInstance Win32_OperatingSystem).OSArchitecture
if ($arch -notlike "*64*") {
    Write-Host "  64-bit Windows required. Detected: $arch" -ForegroundColor Red
    return
}

# ─── Resolve install paths ─────────────────────────────────────────
$InstallDir   = Join-Path $env:LOCALAPPDATA "Programs\360ops"
$BinaryName   = "360ops-desktop.exe"
$BinaryPath   = Join-Path $InstallDir $BinaryName
$StartMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\360ops"
$StartMenuLnk = Join-Path $StartMenuDir "360ops Desktop.lnk"

# ─── Detect existing install ───────────────────────────────────────
$IsUpgrade = $false
$ExistingVersion = $null
if (Test-Path $BinaryPath) {
    try {
        $info = (Get-Item $BinaryPath).VersionInfo
        if ($info.FileVersion) { $ExistingVersion = "v$($info.FileVersion)" }
    } catch {}
    $IsUpgrade = $true
    Write-Host "  Existing install: $InstallDir" -ForegroundColor Gray
    if ($ExistingVersion) { Write-Host "  Current version: $ExistingVersion" -ForegroundColor Gray }
    Write-Host ""
}

# ─── Resolve latest release from public 360ops-releases ────────────
Write-Host "  [1/5] Fetching latest release info..." -ForegroundColor Yellow
$apiUrl = "https://api.github.com/repos/360opsai/360ops-releases/releases"
try {
    $releases = Invoke-RestMethod -Uri $apiUrl -Headers @{ 'User-Agent' = '360ops-desktop-installer' } -ErrorAction Stop
} catch {
    Write-Host "  Couldn't fetch release info: $_" -ForegroundColor Red
    return
}

# Filter to 360ops-desktop-* tagged releases, take latest by published_at
# (created_at often reflects the tag's underlying commit date, not the
# release publish time, which can backdate newer releases on the list).
$desktopReleases = $releases | Where-Object { $_.tag_name -like "360ops-desktop-*" } | Sort-Object published_at -Descending
if (-not $desktopReleases) {
    Write-Host "  No 360ops-desktop releases found in 360opsai/360ops-releases." -ForegroundColor Red
    return
}
$release  = $desktopReleases | Select-Object -First 1
$tag      = $release.tag_name
$exeAsset = $release.assets | Where-Object { $_.name -like "*.exe" } | Select-Object -First 1
$shaAsset = $release.assets | Where-Object { $_.name -like "*.sha256" } | Select-Object -First 1

if (-not $exeAsset) {
    Write-Host "  No .exe asset on release $tag." -ForegroundColor Red
    return
}

$displayVersion = $tag -replace "^360ops-desktop-", ""
Write-Host "  Latest: $displayVersion ($([math]::Round($exeAsset.size / 1MB, 2)) MB)" -ForegroundColor Green

# Skip if already on latest
if ($IsUpgrade -and $ExistingVersion -eq $displayVersion) {
    Write-Host ""
    Write-Host "  Already on $displayVersion — nothing to install." -ForegroundColor Cyan
    return
}

# ─── Download ──────────────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$tmpExe = Join-Path $env:TEMP "360ops-desktop-$($tag)-$(Get-Random).exe"

Write-Host ""
Write-Host "  [2/5] Downloading..." -ForegroundColor Yellow
try {
    $ProgressPreference = 'Continue'
    Invoke-WebRequest -Uri $exeAsset.browser_download_url -OutFile $tmpExe -UseBasicParsing -ErrorAction Stop
} catch {
    Write-Host "  Download failed: $_" -ForegroundColor Red
    if (Test-Path $tmpExe) { Remove-Item $tmpExe -Force -ErrorAction SilentlyContinue }
    return
}

# ─── Verify SHA-256 ────────────────────────────────────────────────
if ($shaAsset) {
    Write-Host "  [3/5] Verifying SHA-256..." -ForegroundColor Yellow
    $tmpSha = Join-Path $env:TEMP "360ops-desktop-$($tag).sha256"
    try {
        Invoke-WebRequest -Uri $shaAsset.browser_download_url -OutFile $tmpSha -UseBasicParsing -ErrorAction Stop
        $expected = (Get-Content $tmpSha -Raw).Split()[0].Trim().ToLower()
        $actual   = (Get-FileHash -Algorithm SHA256 $tmpExe).Hash.ToLower()
        if ($expected -ne $actual) {
            Write-Host "  SHA-256 mismatch — refusing to install." -ForegroundColor Red
            Write-Host "    Expected: $expected" -ForegroundColor Gray
            Write-Host "    Actual:   $actual"   -ForegroundColor Gray
            Remove-Item $tmpExe -Force -ErrorAction SilentlyContinue
            Remove-Item $tmpSha -Force -ErrorAction SilentlyContinue
            return
        }
        Remove-Item $tmpSha -Force -ErrorAction SilentlyContinue
        Write-Host "  Checksum OK ✓" -ForegroundColor Green
    } catch {
        Write-Host "  Couldn't verify checksum (sidecar fetch failed) — continuing." -ForegroundColor Yellow
    }
} else {
    Write-Host "  [3/5] No SHA-256 sidecar — skipping verify." -ForegroundColor Gray
}

# ─── Install (atomic move) ─────────────────────────────────────────
$running = Get-Process -Name '360ops-desktop' -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "  Stopping running instance..." -ForegroundColor Gray
    $running | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

Write-Host "  [4/5] Installing to $InstallDir" -ForegroundColor Yellow
Move-Item -Path $tmpExe -Destination $BinaryPath -Force

# Start Menu shortcut
New-Item -ItemType Directory -Force -Path $StartMenuDir | Out-Null
$wshell = New-Object -ComObject WScript.Shell
$lnk = $wshell.CreateShortcut($StartMenuLnk)
$lnk.TargetPath       = $BinaryPath
$lnk.WorkingDirectory = $InstallDir
$lnk.Description      = "360ops Desktop — Ambient AI assistant"
$lnk.IconLocation     = "$BinaryPath,0"
$lnk.Save()

# Auto-start on login
$RunKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
try {
    Set-ItemProperty -Path $RunKey -Name "360ops-Desktop" -Value "`"$BinaryPath`"" -Type String -Force
} catch {}

# Add the install dir to USER PATH so `360ops-desktop update` works
# from any PowerShell session without typing the full path. User
# scope only; never touches machine PATH.
try {
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not $userPath) { $userPath = "" }
    if ($userPath -notlike "*$InstallDir*") {
        $newPath = if ($userPath) { "$userPath;$InstallDir" } else { $InstallDir }
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        # Also patch the current session's PATH so the user can run
        # `360ops-desktop` immediately without re-launching PowerShell.
        $env:PATH = "$env:PATH;$InstallDir"
    }
} catch {}

# Track install (silent, never blocks)
try {
    $trackBody = @{ type = "download"; os = "windows"; method = "script"; product = "360ops-desktop"; version = $displayVersion } | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri "https://llyftztfkadrnbtisagn.supabase.co/functions/v1/router-events" -Method POST -ContentType "application/json" -Body $trackBody -TimeoutSec 3 2>$null | Out-Null
} catch {}

# ─── Launch ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  [5/5] Launching 360ops Desktop..." -ForegroundColor Yellow
Start-Process -FilePath $BinaryPath -WorkingDirectory $InstallDir

Write-Host ""
Write-Host ""
Write-Host "  ✓ 360ops Desktop $displayVersion installed!" -ForegroundColor Green
Write-Host ""
Write-Host "  • Press Ctrl+Space anywhere for the chat popup." -ForegroundColor White
Write-Host "  • Push the right edge of any window for the side bar." -ForegroundColor White
Write-Host "  • Tray icon → right-click for Quit / Settings." -ForegroundColor White
Write-Host "  • Auto-starts on login. Re-run installer to upgrade." -ForegroundColor White
Write-Host ""
Write-Host "  Re-run this installer anytime to upgrade." -ForegroundColor Gray
Write-Host ""
