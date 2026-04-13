#!/bin/bash
# 360router Installer for Mac/Linux
# Usage: curl -fsSL https://get.360ops.ai/router | bash
# ──────────────────────────────────────────────────────

set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo -e "  ${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "  ${CYAN}║         360router Installer           ║${NC}"
echo -e "  ${CYAN}║   Smart AI Router - Local First       ║${NC}"
echo -e "  ${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""

# Step 1: Check Node.js
echo -e "  ${YELLOW}[1/3] Checking Node.js...${NC}"

if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    MAJOR=$(echo "$NODE_VERSION" | sed 's/v\([0-9]*\).*/\1/')

    if [ "$MAJOR" -lt 18 ]; then
        echo -e "  ${RED}Node.js $NODE_VERSION found but v18+ required.${NC}"
        echo -e "  ${RED}Please update: https://nodejs.org${NC}"
        exit 1
    fi
    echo -e "  ${GREEN}Node.js $NODE_VERSION${NC}"
else
    echo -e "  ${YELLOW}Node.js not found. Installing...${NC}"

    # Detect OS and install
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            echo -e "  ${YELLOW}Installing via Homebrew...${NC}"
            brew install node@20
        else
            echo -e "  ${YELLOW}Installing via official installer...${NC}"
            curl -fsSL https://nodejs.org/dist/v20.12.0/node-v20.12.0.pkg -o /tmp/node.pkg
            sudo installer -pkg /tmp/node.pkg -target /
            rm -f /tmp/node.pkg
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        if command -v apt &> /dev/null; then
            echo -e "  ${YELLOW}Installing via apt...${NC}"
            curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
            sudo apt install -y nodejs
        elif command -v yum &> /dev/null; then
            curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
            sudo yum install -y nodejs
        else
            echo -e "  ${RED}Please install Node.js 18+ from: https://nodejs.org${NC}"
            exit 1
        fi
    fi

    # Verify
    if ! command -v node &> /dev/null; then
        echo -e "  ${RED}Node.js installation failed. Please install manually from https://nodejs.org${NC}"
        exit 1
    fi
    echo -e "  ${GREEN}Node.js $(node --version)${NC}"
fi

# Step 2: Install 360router
echo -e "  ${YELLOW}[2/3] Installing 360router...${NC}"
npm install -g 360router 2>/dev/null || sudo npm install -g 360router 2>/dev/null

# Verify
if ! command -v 360router &> /dev/null; then
    echo -e "  ${RED}Installation failed. Try manually: npm install -g 360router${NC}"
    exit 1
fi
echo -e "  ${GREEN}360router installed${NC}"

# Step 3: Launch setup wizard
echo -e "  ${YELLOW}[3/3] Launching setup wizard...${NC}"
echo ""
echo -e "  ${CYAN}════════════════════════════════════════${NC}"
echo ""

360router init
