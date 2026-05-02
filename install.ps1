# 360ops Desktop installer — PowerShell one-liner.
#
# Usage from any PowerShell prompt (no admin required):
#
#   irm https://raw.githubusercontent.com/360opsai/360ops-windows/main/install.ps1 | iex
#
# What it does:
#   1. Detect existing install + offer upgrade
#   2. Fetch latest release info from GitHub Releases API
#   3. Download `360ops-anchor-vX.Y.Z.exe` to LocalAppData
#   4. Verify SHA-256 against the .sha256 sidecar
#   5. Create Start Menu shortcut + Desktop shortcut (optional)
#   6. Register for auto-start on login (optional)
#   7. Launch the binary
#
# Doesn't need admin: installs to %LOCALAPPDATA%\Programs\360ops\,
# Start Menu shortcut goes in the user's Programs folder, no system
# changes. To uninstall: delete the install dir + shortcuts.

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ─── Branding banner ────────────────────────────────────────────────
# Cyan #00E5FF + Orbitron-style ASCII. Using foreground colors that
# render OK in Windows Terminal + classic ConHost.
$Cyan    = "`e[38;2;0;229;255m"
$Cyan2   = "`e[38;2;0;168;189m"
$Cayenne = "`e[38;2;255;107;53m"
$Reset   = "`e[0m"
$Bold    = "`e[1m"
$Dim     = "`e[2m"

Write-Host ""
Write-Host "${Cyan}${Bold}    ╭──────────────────────────────────────╮${Reset}"
Write-Host "${Cyan}${Bold}    │   3 6 0   O P S   D E S K T O P     │${Reset}"
Write-Host "${Cyan}${Bold}    ╰──────────────────────────────────────╯${Reset}"
Write-Host ""

# ─── Sanity checks ──────────────────────────────────────────────────
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "${Cayenne}This installer needs PowerShell 5.0 or newer.${Reset}"
    Write-Host "Run from Windows PowerShell or PowerShell 7."
    exit 1
}

# Windows-only for now (macOS / Linux installers ship later).
if ($IsLinux -or $IsMacOS) {
    Write-Host "${Cayenne}This installer is for Windows only.${Reset}"
    Write-Host "macOS + Linux builds are coming. For now, see"
    Write-Host "${Dim}  https://github.com/360opsai/360ops-windows/releases/latest${Reset}"
    exit 1
}

# Architecture check — only x64 builds for v0.0.x.
$arch = (Get-CimInstance Win32_OperatingSystem).OSArchitecture
if ($arch -notlike "*64*") {
    Write-Host "${Cayenne}360ops Desktop requires a 64-bit Windows machine.${Reset}"
    Write-Host "Detected: $arch"
    exit 1
}

# ─── Resolve install paths ──────────────────────────────────────────
$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\360ops"
$BinaryName = "360ops-anchor.exe"
$BinaryPath = Join-Path $InstallDir $BinaryName

$StartMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\360ops"
$StartMenuShortcut = Join-Path $StartMenuDir "360ops Desktop.lnk"

$DesktopShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) "360ops Desktop.lnk"

# ─── Detect existing install ────────────────────────────────────────
$IsUpgrade = $false
$ExistingVersion = $null
if (Test-Path $BinaryPath) {
    try {
        $info = (Get-Item $BinaryPath).VersionInfo
        if ($info.FileVersion) {
            $ExistingVersion = "v$($info.FileVersion)"
        }
    } catch { }
    $IsUpgrade = $true
    Write-Host "${Dim}Existing install detected${Reset}: $InstallDir"
    if ($ExistingVersion) { Write-Host "${Dim}Current version${Reset}: $ExistingVersion" }
    Write-Host ""
}

# ─── Resolve latest release ─────────────────────────────────────────
Write-Host "${Cyan}> Fetching latest release info...${Reset}"
$apiUrl = "https://api.github.com/repos/360opsai/360ops-windows/releases/latest"
try {
    $release = Invoke-RestMethod -Uri $apiUrl -Headers @{ 'User-Agent' = '360ops-installer' } -ErrorAction Stop
} catch {
    Write-Host "${Cayenne}Couldn't fetch release info.${Reset}"
    Write-Host "$_"
    exit 1
}

$tag = $release.tag_name
$exeAsset = $release.assets | Where-Object { $_.name -like "*.exe" } | Select-Object -First 1
$shaAsset = $release.assets | Where-Object { $_.name -like "*.sha256" } | Select-Object -First 1

if (-not $exeAsset) {
    Write-Host "${Cayenne}No .exe asset on the latest release.${Reset}"
    Write-Host "Browse: https://github.com/360opsai/360ops-windows/releases"
    exit 1
}

Write-Host "${Cyan}> Latest release${Reset}: $tag"
Write-Host "${Cyan}> Asset${Reset}: $($exeAsset.name) ($([math]::Round($exeAsset.size / 1MB, 2)) MB)"

# Skip-if-already-on-latest check.
if ($IsUpgrade -and $ExistingVersion -eq $tag) {
    Write-Host ""
    Write-Host "${Cyan}Already on $tag${Reset} — nothing to install."
    Write-Host "${Dim}To force a reinstall, delete $InstallDir first.${Reset}"
    exit 0
}

# ─── Download ───────────────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$tmpExe = Join-Path $env:TEMP "360ops-anchor-$($tag)-$(Get-Random).exe"

Write-Host ""
Write-Host "${Cyan}> Downloading...${Reset}"
try {
    $ProgressPreference = 'Continue'
    Invoke-WebRequest -Uri $exeAsset.browser_download_url -OutFile $tmpExe -UseBasicParsing -ErrorAction Stop
} catch {
    Write-Host "${Cayenne}Download failed.${Reset}"
    Write-Host "$_"
    if (Test-Path $tmpExe) { Remove-Item $tmpExe -Force -ErrorAction SilentlyContinue }
    exit 1
}

# ─── Verify SHA-256 ─────────────────────────────────────────────────
if ($shaAsset) {
    Write-Host "${Cyan}> Verifying SHA-256...${Reset}"
    $tmpSha = Join-Path $env:TEMP "360ops-anchor-$($tag).sha256"
    try {
        Invoke-WebRequest -Uri $shaAsset.browser_download_url -OutFile $tmpSha -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Host "${Cayenne}Couldn't fetch SHA-256 sidecar — skipping verify.${Reset}"
        $tmpSha = $null
    }
    if ($tmpSha) {
        $expected = (Get-Content $tmpSha -Raw).Split()[0].Trim().ToLower()
        $actual = (Get-FileHash -Algorithm SHA256 $tmpExe).Hash.ToLower()
        if ($expected -ne $actual) {
            Write-Host "${Cayenne}SHA-256 mismatch — refusing to install.${Reset}"
            Write-Host "  Expected: $expected"
            Write-Host "  Actual:   $actual"
            Remove-Item $tmpExe -Force -ErrorAction SilentlyContinue
            Remove-Item $tmpSha -Force -ErrorAction SilentlyContinue
            exit 1
        }
        Remove-Item $tmpSha -Force -ErrorAction SilentlyContinue
        Write-Host "${Cyan}  ✓ checksum matches${Reset}"
    }
} else {
    Write-Host "${Dim}> No SHA-256 sidecar published — skipping verify.${Reset}"
}

# ─── Install (atomic move) ──────────────────────────────────────────
# If a prior process is running, stop it so the file isn't locked.
$running = Get-Process -Name '360ops-anchor' -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "${Cyan}> Stopping running instance...${Reset}"
    $running | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

Write-Host "${Cyan}> Installing to${Reset} $InstallDir"
Move-Item -Path $tmpExe -Destination $BinaryPath -Force

# ─── Start Menu shortcut ────────────────────────────────────────────
Write-Host "${Cyan}> Creating Start Menu shortcut...${Reset}"
New-Item -ItemType Directory -Force -Path $StartMenuDir | Out-Null
$wshell = New-Object -ComObject WScript.Shell
$lnk = $wshell.CreateShortcut($StartMenuShortcut)
$lnk.TargetPath = $BinaryPath
$lnk.WorkingDirectory = $InstallDir
$lnk.Description = "360ops Desktop — Ambient AI assistant"
$lnk.IconLocation = "$BinaryPath,0"
$lnk.Save()

# ─── Desktop shortcut (skipped on auto / iex pipe — too easy to clutter) ─
# (kept commented as a power-user opt-in for the future.)
# $lnkDesk = $wshell.CreateShortcut($DesktopShortcut)
# $lnkDesk.TargetPath = $BinaryPath
# $lnkDesk.WorkingDirectory = $InstallDir
# $lnkDesk.Save()

# ─── Auto-start on login (always on for now — quick toggle if user objects) ─
$RunKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
try {
    Set-ItemProperty -Path $RunKey -Name "360ops-Desktop" -Value "`"$BinaryPath`"" -Type String -Force
    Write-Host "${Cyan}> Registered for auto-start on login${Reset}"
} catch {
    Write-Host "${Dim}> Couldn't register auto-start (non-fatal).${Reset}"
}

# ─── Launch ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "${Cyan}${Bold}> Launching 360ops Desktop...${Reset}"
Start-Process -FilePath $BinaryPath -WorkingDirectory $InstallDir

Write-Host ""
Write-Host "${Cyan}╭──────────────────────────────────────────────────────╮${Reset}"
Write-Host "${Cyan}│${Reset}  ${Bold}Installed $tag${Reset}                                       ${Cyan}│${Reset}"
Write-Host "${Cyan}│${Reset}                                                      ${Cyan}│${Reset}"
Write-Host "${Cyan}│${Reset}  Press ${Bold}Ctrl+Space${Reset} anywhere to open the chat popup.    ${Cyan}│${Reset}"
Write-Host "${Cyan}│${Reset}  Hover the right edge of any window for the side bar.${Cyan}│${Reset}"
Write-Host "${Cyan}│${Reset}                                                      ${Cyan}│${Reset}"
Write-Host "${Cyan}│${Reset}  Tray icon → right-click for Quit / Settings.        ${Cyan}│${Reset}"
Write-Host "${Cyan}╰──────────────────────────────────────────────────────╯${Reset}"
Write-Host ""
Write-Host "${Dim}To uninstall: delete $InstallDir + the Start Menu shortcut.${Reset}"
Write-Host "${Dim}Updates: re-run this command anytime — auto-detects + upgrades.${Reset}"
Write-Host ""
