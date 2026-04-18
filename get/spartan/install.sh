#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# SPARTAN 360ops — License-Gated Bootstrap Installer v1.0.0
# ═══════════════════════════════════════════════════════════════════════════
#
# Customer flow:
#   1. Buy license at portal.360ops.ai/spartan/buy
#   2. Receive license key by email
#   3. Run: curl -fsSL https://get.360ops.ai/spartan/install.sh | \
#          sudo SPARTAN_LICENSE=xxx bash
#   4. This script:
#      - Validates license against console.360ops.ai
#      - Downloads tarball from R2 signed URL (5-min TTL)
#      - Verifies SHA-256
#      - Installs to /opt/spartan
#
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────
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

# ── Build hardware fingerprint ───────────────────────────────────────────
step "Building hardware fingerprint"
CPU_MODEL=$(lscpu | grep 'Model name' | head -1 || echo "unknown")
MAC_ADDR=$(ip link | awk '/link\/ether/{print $2; exit}' || echo "unknown")
DISK_SERIAL=$(lsblk -dno SERIAL /dev/nvme0n1 2>/dev/null | head -1 || lsblk -dno SERIAL /dev/sda 2>/dev/null | head -1 || echo "unknown")

HW_FINGERPRINT=$(echo "${CPU_MODEL}${MAC_ADDR}${DISK_SERIAL}" | sha256sum | awk '{print $1}')
ok "Fingerprint: ${HW_FINGERPRINT:0:16}..."

# ── License Key ───────────────────────────────────────────────────────────
step "License Activation"

if [[ -z "${SPARTAN_LICENSE:-}" ]]; then
  if [[ -t 0 ]]; then
    echo ""
    echo "  You need a Spartan license key to continue."
    echo "  Get one at: ${CYAN}https://portal.360ops.ai/spartan/buy${RESET}"
    echo ""
    read -p "  License key: " SPARTAN_LICENSE
  elif [[ -r /dev/tty ]]; then
    echo ""
    echo "  You need a Spartan license key to continue."
    echo "  Get one at: ${CYAN}https://portal.360ops.ai/spartan/buy${RESET}"
    echo ""
    read -p "  License key: " SPARTAN_LICENSE < /dev/tty
  else
    fail "No license key. Set SPARTAN_LICENSE env var or run interactively"
  fi
fi

if [[ -z "${SPARTAN_LICENSE:-}" ]]; then
  fail "License key cannot be empty"
fi

# Box identity
if [[ -z "${BOX_ID:-}" ]]; then
  BOX_ID="spartan-$(hostname -s)-$(date +%s | tail -c 5)"
fi

ok "License captured (masked): ${SPARTAN_LICENSE:0:8}...${SPARTAN_LICENSE: -4}"
ok "Box ID: $BOX_ID"

# ── Console reachability check ────────────────────────────────────────────
step "Checking console reachability"

if ! command -v curl &>/dev/null; then
  info "Installing curl..."
  DEBIAN_FRONTEND=noninteractive apt-get update -y -qq >> "$INSTALL_LOG" 2>&1
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates >> "$INSTALL_LOG" 2>&1
fi

if [[ "${SPARTAN_ALLOW_OFFLINE:-}" != "1" ]]; then
  if ! curl -fsSL --max-time 5 "$LICENSE_SERVER/api/health" &>/dev/null; then
    fail "Box cannot reach $LICENSE_SERVER — check firewall egress rules.
         For air-gapped installs set SPARTAN_ALLOW_OFFLINE=1 (requires pre-staged tarball)"
  fi
  ok "Console reachable at $LICENSE_SERVER"
fi

# Install jq if missing (needed to parse activate response)
if ! command -v jq &>/dev/null; then
  info "Installing jq..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq jq >> "$INSTALL_LOG" 2>&1
fi

# ── Call activate API ─────────────────────────────────────────────────────
step "Activating license with console"

ACTIVATE_RESPONSE=$(curl -fsSL -X POST "$LICENSE_SERVER/api/spartan/activate" \
  -H "Content-Type: application/json" \
  --max-time 15 \
  -d "{\"license\":\"$SPARTAN_LICENSE\",\"box_id\":\"$BOX_ID\",\"hw_fingerprint\":\"$HW_FINGERPRINT\",\"hostname\":\"$(hostname)\",\"user_agent\":\"spartan-bootstrap/1.0.0\"}" \
  2>&1 || echo '{"error":"network_failure"}')

# Parse response
ERROR=$(echo "$ACTIVATE_RESPONSE" | jq -r '.error // empty' 2>/dev/null || echo "")
HTTP_STATUS=$(echo "$ACTIVATE_RESPONSE" | jq -r '.status // empty' 2>/dev/null || echo "")

if [[ -n "$ERROR" ]] || [[ "$HTTP_STATUS" == "401" ]]; then
  fail "License activation failed: Invalid license key"
elif [[ "$HTTP_STATUS" == "402" ]]; then
  fail "License activation failed: Payment failed — check billing at portal.360ops.ai"
elif [[ "$HTTP_STATUS" == "403" ]]; then
  fail "License activation failed: Seat limit exceeded — upgrade your plan or deactivate a box"
elif [[ -n "$ERROR" ]]; then
  fail "License activation failed: $ERROR"
fi

ACTIVATION_TOKEN=$(echo "$ACTIVATE_RESPONSE" | jq -r '.activation_token // empty')
DOWNLOAD_URL=$(echo "$ACTIVATE_RESPONSE" | jq -r '.download_url // empty')
SHA256=$(echo "$ACTIVATE_RESPONSE" | jq -r '.sha256 // empty')
TIER=$(echo "$ACTIVATE_RESPONSE" | jq -r '.tier // "solo"')
BOX_LIMIT=$(echo "$ACTIVATE_RESPONSE" | jq -r '.box_limit // 1')
EXPIRES_AT=$(echo "$ACTIVATE_RESPONSE" | jq -r '.expires_at // empty')
HEARTBEAT_INTERVAL_SEC=$(echo "$ACTIVATE_RESPONSE" | jq -r '.heartbeat_interval_sec // 300')
CONSOLE_URL=$(echo "$ACTIVATE_RESPONSE" | jq -r '.console_url // empty')

if [[ -z "$ACTIVATION_TOKEN" ]] || [[ -z "$DOWNLOAD_URL" ]] || [[ -z "$SHA256" ]]; then
  fail "Invalid activation response from console — missing required fields"
fi

ok "License activated (tier: $TIER, box_limit: $BOX_LIMIT)"
ok "Activation token: ${ACTIVATION_TOKEN:0:16}..."

# ── Download tarball ──────────────────────────────────────────────────────
step "Downloading Spartan release"

TARBALL="/tmp/spartan-release.tar.gz"
info "Downloading from R2..."

if ! curl -fsSL -o "$TARBALL" "$DOWNLOAD_URL"; then
  fail "Download failed from signed URL — check network or contact support"
fi

DOWNLOADED_SIZE=$(du -h "$TARBALL" | awk '{print $1}')
ok "Downloaded $DOWNLOADED_SIZE"

# ── Verify SHA-256 ────────────────────────────────────────────────────────
step "Verifying tarball integrity"

COMPUTED_SHA256=$(sha256sum "$TARBALL" | awk '{print $1}')

if [[ "$COMPUTED_SHA256" != "$SHA256" ]]; then
  fail "SHA-256 mismatch!
       Expected: $SHA256
       Got:      $COMPUTED_SHA256
       Possible MITM attack or corrupted download."
fi

ok "SHA-256 verified: ${SHA256:0:16}..."

# ── Extract ───────────────────────────────────────────────────────────────
step "Installing to $INSTALL_DIR"

# Backup existing install if present
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

# ── Export vars for child scripts ─────────────────────────────────────────
export SPARTAN_LICENSE BOX_ID HW_FINGERPRINT ACTIVATION_TOKEN
export TIER BOX_LIMIT LICENSE_SERVER CONSOLE_URL HEARTBEAT_INTERVAL_SEC
export INSTALL_DIR SPARTAN_USER HAS_NVIDIA GPU_VRAM_MB
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
echo -e "  ${DIM}Box ID: $BOX_ID  |  Tier: $TIER  |  Token: ${ACTIVATION_TOKEN:0:12}...${RESET}"
echo ""
