#!/bin/bash
# 360router Installer for Mac/Linux — Binary distribution
# Usage: curl -fsSL https://get.360ops.ai/router | bash
# ──────────────────────────────────────────────────────
#
# Downloads the signed 360router binary from GitHub Releases.
# No Node.js required. No source code shipped.
# Existing configuration is preserved across upgrades.

set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo -e "  ${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "  ${CYAN}║         360Router Installer          ║${NC}"
echo -e "  ${CYAN}║   Smart AI Router - Local First      ║${NC}"
echo -e "  ${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""

# Detect platform
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Linux*)
        BINARY_NAME="360router-linux"
        ;;
    Darwin*)
        BINARY_NAME="360router-mac"
        ;;
    *)
        echo -e "  ${RED}Unsupported OS: $OS${NC}"
        exit 1
        ;;
esac

RELEASE_URL="https://github.com/360opsai/360ops-portal/releases/latest/download/${BINARY_NAME}"
INSTALL_DIR="$HOME/.local/bin"
INSTALL_BIN="$INSTALL_DIR/360router"

# Detect existing install
if [ -x "$INSTALL_BIN" ]; then
    IS_UPGRADE=1
else
    IS_UPGRADE=0
fi

# Detect existing config (conf package default location)
if [[ "$OS" == "Darwin" ]]; then
    CONFIG_PATH="$HOME/Library/Preferences/360router-nodejs/config.json"
else
    CONFIG_PATH="$HOME/.config/360router-nodejs/config.json"
fi

if [ -f "$CONFIG_PATH" ]; then
    HAS_CONFIG=1
else
    HAS_CONFIG=0
fi

# Step 1: Prepare install dir
echo -e "  ${YELLOW}[1/3] Preparing install directory...${NC}"
mkdir -p "$INSTALL_DIR"
echo -e "  ${GREEN}$INSTALL_DIR${NC}"

# Step 2: Download
echo ""
if [ "$IS_UPGRADE" = "1" ]; then
    echo -e "  ${YELLOW}[2/3] Upgrading 360router...${NC}"
else
    echo -e "  ${YELLOW}[2/3] Downloading 360router...${NC}"
fi

if command -v curl &>/dev/null; then
    curl -fSL "$RELEASE_URL" -o "$INSTALL_BIN"
elif command -v wget &>/dev/null; then
    wget -q "$RELEASE_URL" -O "$INSTALL_BIN"
else
    echo -e "  ${RED}Neither curl nor wget is available. Install one and retry.${NC}"
    exit 1
fi

chmod +x "$INSTALL_BIN"
SIZE_MB=$(du -m "$INSTALL_BIN" | cut -f1)
echo -e "  ${GREEN}Downloaded ${SIZE_MB} MB${NC}"

# Step 3: Add to PATH if missing
if ! echo ":$PATH:" | grep -q ":$INSTALL_DIR:"; then
    SHELL_RC=""
    if [ -n "$BASH_VERSION" ] || [ -f "$HOME/.bashrc" ]; then
        SHELL_RC="$HOME/.bashrc"
    elif [ -n "$ZSH_VERSION" ] || [ -f "$HOME/.zshrc" ]; then
        SHELL_RC="$HOME/.zshrc"
    fi

    if [ -n "$SHELL_RC" ] && ! grep -q "360router" "$SHELL_RC" 2>/dev/null; then
        echo "" >> "$SHELL_RC"
        echo "# 360router" >> "$SHELL_RC"
        echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$SHELL_RC"
        echo -e "  ${YELLOW}Added to PATH (in $SHELL_RC)${NC}"
        echo -e "  ${YELLOW}Run 'source $SHELL_RC' or start a new terminal${NC}"
    fi
fi

# Verify
if ! VERSION=$("$INSTALL_BIN" --version 2>/dev/null); then
    echo -e "  ${RED}Installation incomplete. Try: $INSTALL_BIN --version${NC}"
    exit 1
fi
echo -e "  ${GREEN}360router v$VERSION${NC}"

# Track install (silent, never blocks)
curl -s -X POST "https://llyftztfkadrnbtisagn.supabase.co/functions/v1/router-events" \
  -H "Content-Type: application/json" \
  -d "{\"type\":\"download\",\"os\":\"$OS\",\"method\":\"script\",\"version\":\"$VERSION\"}" \
  --max-time 3 >/dev/null 2>&1 &

# Step 4: Configuration
echo ""
echo -e "  ${YELLOW}[3/3] Configuration...${NC}"

if [ "$HAS_CONFIG" = "1" ]; then
    echo -e "  ${GREEN}Existing configuration detected — preserved.${NC}"
    echo ""
    echo -e "  ${CYAN}════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Your API keys, providers, and preferences are intact."
    echo ""
    echo -e "  To reconfigure:      ${CYAN}360router init${NC}"
    echo -e "  To edit a setting:   ${CYAN}360router config set${NC}"
    echo -e "  To start the proxy:  ${CYAN}360router serve${NC}"
    echo ""
    exit 0
fi

# First-time install
echo -e "  ${YELLOW}First-time install — launching setup wizard...${NC}"
echo ""
echo -e "  ${CYAN}════════════════════════════════════════${NC}"
echo ""

"$INSTALL_BIN" init
