#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# SPARTAN 360ops — One-Line Bootstrap Installer
# ═══════════════════════════════════════════════════════════════════════════
# Usage (interactive):
#   curl -fsSL https://get.360ops.ai/spartan/install.sh | sudo bash
#
# Usage (scripted):
#   curl -fsSL https://get.360ops.ai/spartan/install.sh | \
#     sudo SPARTAN_LICENSE=xxx BOX_ID=dgx-prod-01 CLIENT_NAME="Acme" bash
#
# What this does:
#   1. Preflight hardware check (bails if too small)
#   2. Prompts for (or reads) license key
#   3. Downloads latest Spartan release tarball from GitHub
#   4. Extracts to /opt/spartan
#   5. Creates 'spartan' system user
#   6. Hands off to install-deps.sh + install-app.sh inside the tarball
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────
RELEASES_REPO="${RELEASES_REPO:-istninc/360ops-releases}"
RELEASE_TAG="${RELEASE_TAG:-spartan-latest}"
INSTALL_DIR="${INSTALL_DIR:-/opt/spartan}"
SPARTAN_USER="${SPARTAN_USER:-spartan}"
LICENSE_SERVER="${LICENSE_SERVER:-https://console.360ops.ai}"

# ── Colors ────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

ok()   { echo -e "  ${GREEN}✔${RESET}  $*"; }
info() { echo -e "  ${CYAN}→${RESET}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
fail() { echo -e "  ${RED}✘${RESET}  $*" >&2; exit 1; }
step() { echo -e "\n${BOLD}▶ $*${RESET}"; }

# ── Banner ────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║              SPARTAN 360ops — One-Line Install           ║${RESET}"
echo -e "${CYAN}${BOLD}║              On-prem sovereign AI platform               ║${RESET}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""

# ── Root check ────────────────────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
  fail "This installer must run as root. Try: curl -fsSL https://get.360ops.ai/spartan/install.sh | sudo bash"
fi

INSTALL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
INSTALL_LOG="/var/log/spartan-install.log"
mkdir -p "$(dirname "$INSTALL_LOG")"
touch "$INSTALL_LOG"
echo "=== SPARTAN INSTALL $(date -Iseconds) ===" >> "$INSTALL_LOG"

# ── OS check ──────────────────────────────────────────────────────────────
step "Checking OS"
if [[ ! -f /etc/os-release ]]; then
  fail "Cannot detect OS — /etc/os-release missing"
fi
. /etc/os-release
case "$ID" in
  ubuntu)
    case "$VERSION_ID" in
      22.04|24.04) ok "Ubuntu $VERSION_ID — supported" ;;
      *) warn "Ubuntu $VERSION_ID is not officially supported (22.04 / 24.04 only). Continuing anyway." ;;
    esac
    ;;
  debian)
    warn "Debian detected — community-supported. Continuing."
    ;;
  *)
    fail "Unsupported OS: $ID. Spartan supports Ubuntu 22.04 and 24.04 LTS."
    ;;
esac

# ── Preflight: Hardware ───────────────────────────────────────────────────
step "Preflight — Hardware Check"

CPU_CORES=$(nproc)
RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
DISK_FREE_GB=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
HAS_NVIDIA="no"
GPU_VRAM_MB=0
GPU_NAME="none"

if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
  HAS_NVIDIA="yes"
  GPU_VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
  GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
fi

echo "    CPU cores:   $CPU_CORES"
echo "    RAM:         ${RAM_GB} GB"
echo "    Disk free:   ${DISK_FREE_GB} GB"
echo "    GPU:         $GPU_NAME ($([ $GPU_VRAM_MB -gt 0 ] && echo "${GPU_VRAM_MB} MiB VRAM" || echo "CPU-only"))"
echo ""

# Minimums
MIN_CORES=4
MIN_RAM=16
MIN_DISK=40

if (( CPU_CORES < MIN_CORES )); then
  fail "Need ≥${MIN_CORES} CPU cores (have $CPU_CORES)"
fi
if (( RAM_GB < MIN_RAM )); then
  fail "Need ≥${MIN_RAM} GB RAM (have ${RAM_GB} GB)"
fi
if (( DISK_FREE_GB < MIN_DISK )); then
  fail "Need ≥${MIN_DISK} GB free disk (have ${DISK_FREE_GB} GB)"
fi
ok "Hardware OK"

# ── License Key ───────────────────────────────────────────────────────────
step "License Activation"

if [[ -z "${SPARTAN_LICENSE:-}" ]]; then
  # Interactive prompt — but only if we have a TTY. If piped without TTY, fail.
  if [[ -t 0 ]]; then
    echo ""
    echo "  You need a Spartan license key to continue."
    echo "  Get one at: ${CYAN}https://console.360ops.ai/licenses${RESET}"
    echo ""
    read -p "  License key: " SPARTAN_LICENSE
  elif [[ -r /dev/tty ]]; then
    echo ""
    echo "  You need a Spartan license key to continue."
    echo "  Get one at: ${CYAN}https://console.360ops.ai/licenses${RESET}"
    echo ""
    read -p "  License key: " SPARTAN_LICENSE < /dev/tty
  else
    fail "No license key. Set SPARTAN_LICENSE env var or run interactively:
         curl -fsSL https://get.360ops.ai/spartan/install.sh | sudo SPARTAN_LICENSE=xxx bash"
  fi
fi

if [[ -z "${SPARTAN_LICENSE:-}" ]]; then
  fail "License key cannot be empty"
fi

# Client + Box identity (prompt if missing)
if [[ -z "${CLIENT_NAME:-}" ]]; then
  if [[ -t 0 ]] || [[ -r /dev/tty ]]; then
    read -p "  Client / Organization name: " CLIENT_NAME < "${BASH_SOURCE[0]:-/dev/tty}" 2>/dev/null || \
    read -p "  Client / Organization name: " CLIENT_NAME
  fi
  CLIENT_NAME="${CLIENT_NAME:-Spartan Customer}"
fi

if [[ -z "${BOX_ID:-}" ]]; then
  BOX_ID="spartan-$(hostname -s)-$(date +%s | tail -c 5)"
fi

ok "License captured (masked): ${SPARTAN_LICENSE:0:4}...${SPARTAN_LICENSE: -4}"
ok "Client: $CLIENT_NAME"
ok "Box ID: $BOX_ID"

# ── Verify license with console (soft-fail to grace mode) ────────────────
step "Verifying license with $LICENSE_SERVER"
LICENSE_STATUS="unknown"
if command -v curl &>/dev/null; then
  LICENSE_RESPONSE=$(curl -fsSL --max-time 10 \
    -X POST "$LICENSE_SERVER/api/licenses/activate" \
    -H "Content-Type: application/json" \
    -d "{\"license\":\"$SPARTAN_LICENSE\",\"box_id\":\"$BOX_ID\",\"hostname\":\"$(hostname)\"}" \
    2>/dev/null || echo "")
  if [[ -n "$LICENSE_RESPONSE" ]]; then
    LICENSE_STATUS="activated"
    ok "License verified online"
  else
    LICENSE_STATUS="grace"
    warn "License server unreachable — entering 7-day grace period (will retry in background)"
  fi
fi

# ── Download release tarball ──────────────────────────────────────────────
step "Downloading Spartan release"

if ! command -v curl &>/dev/null; then
  info "Installing curl..."
  DEBIAN_FRONTEND=noninteractive apt-get update -y -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates
fi

# Resolve tag
if [[ "$RELEASE_TAG" == "spartan-latest" ]]; then
  info "Resolving latest Spartan release tag..."
  TAG=$(curl -fsSL "https://api.github.com/repos/$RELEASES_REPO/releases" | \
        grep '"tag_name"' | grep -o 'spartan-v[0-9.]*' | head -1)
  if [[ -z "$TAG" ]]; then
    fail "Could not find any spartan-v* release in $RELEASES_REPO"
  fi
else
  TAG="$RELEASE_TAG"
fi

TARBALL_URL="https://github.com/$RELEASES_REPO/releases/download/$TAG/spartan-${TAG#spartan-}.tar.gz"
TARBALL="/tmp/spartan-${TAG}.tar.gz"

info "Downloading $TAG..."
info "  $TARBALL_URL"
if ! curl -fsSL -o "$TARBALL" "$TARBALL_URL"; then
  fail "Download failed — check network and that release $TAG exists at $TARBALL_URL"
fi
ok "Downloaded $(du -h "$TARBALL" | awk '{print $1}')"

# ── Extract ───────────────────────────────────────────────────────────────
step "Installing to $INSTALL_DIR"

# If existing install, back it up
if [[ -d "$INSTALL_DIR" ]] && [[ -f "$INSTALL_DIR/package.json" ]]; then
  BACKUP="$INSTALL_DIR.backup-$(date +%Y%m%d-%H%M%S)"
  info "Existing install found — backing up to $BACKUP"
  mv "$INSTALL_DIR" "$BACKUP"
fi

mkdir -p "$INSTALL_DIR"
tar -xzf "$TARBALL" -C "$INSTALL_DIR" --strip-components=1
ok "Extracted to $INSTALL_DIR"

# ── Create spartan system user ────────────────────────────────────────────
step "Creating spartan system user"
if id "$SPARTAN_USER" &>/dev/null; then
  ok "User '$SPARTAN_USER' already exists"
else
  useradd --system --home "$INSTALL_DIR" --shell /bin/bash "$SPARTAN_USER"
  ok "User '$SPARTAN_USER' created"
fi
chown -R "$SPARTAN_USER:$SPARTAN_USER" "$INSTALL_DIR"

# ── Export vars for inner scripts ─────────────────────────────────────────
export SPARTAN_LICENSE BOX_ID CLIENT_NAME LICENSE_STATUS INSTALL_DIR
export SPARTAN_USER LICENSE_SERVER HAS_NVIDIA GPU_VRAM_MB GPU_NAME
export RAM_GB CPU_CORES INSTALL_LOG

# ── Hand off to deps + app installers ─────────────────────────────────────
step "Installing system dependencies"
bash "$INSTALL_DIR/deploy/install-deps.sh" 2>&1 | tee -a "$INSTALL_LOG"

step "Configuring Spartan application"
bash "$INSTALL_DIR/deploy/install-app.sh" 2>&1 | tee -a "$INSTALL_LOG"

# ── Done ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}${BOLD}║               SPARTAN INSTALL COMPLETE                   ║${RESET}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""
LAN_IP=$(hostname -I | awk '{print $1}')
echo -e "  ${BOLD}Portal:${RESET}   http://${LAN_IP}:3000"
echo -e "  ${BOLD}Switch:${RESET}   http://${LAN_IP}:4000"
echo -e "  ${BOLD}Logs:${RESET}     $INSTALL_LOG"
echo -e "  ${BOLD}Status:${RESET}   sudo -u $SPARTAN_USER pm2 status"
echo ""
echo -e "  ${DIM}Box ID: $BOX_ID  |  License: ${LICENSE_STATUS}${RESET}"
echo ""
