#!/bin/bash
set -euo pipefail

# Install tools required to run the full CI pipeline locally.
# Supports Ubuntu/Debian, macOS (Homebrew), and Alpine.

# Colors (disabled in CI)
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  NC='\033[0m'
else
  GREEN='' RED='' NC=''
fi

ok()   { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }

need_cmd() {
  if command -v "$1" &>/dev/null; then
    ok "$1 already installed ($(command -v "$1"))"
    return 1
  fi
  return 0
}

echo "==> Installing CI dependencies"
echo ""

# --- Node.js / npm ---
if ! command -v node &>/dev/null; then
  fail "Node.js is required but not installed. Install it from https://nodejs.org"
  exit 1
fi
ok "node $(node --version)"

# --- shellcheck ---
if need_cmd shellcheck; then
  echo "    Installing shellcheck..."
  if command -v apt-get &>/dev/null; then
    sudo apt-get update -qq && sudo apt-get install -y -qq shellcheck
  elif command -v brew &>/dev/null; then
    brew install shellcheck
  elif command -v apk &>/dev/null; then
    sudo apk add --no-cache shellcheck
  else
    fail "Could not install shellcheck — install it manually: https://github.com/koalaman/shellcheck#installing"
    exit 1
  fi
  ok "shellcheck installed"
fi

# --- markdownlint-cli2 ---
if need_cmd markdownlint-cli2; then
  echo "    Installing markdownlint-cli2..."
  npm install -g markdownlint-cli2
  ok "markdownlint-cli2 installed"
fi

# --- tessl ---
if need_cmd tessl; then
  echo "    Installing tessl..."
  npm install -g tessl
  ok "tessl installed"
fi

echo ""
echo "==> All CI tools installed. You can now run:"
echo "    bash scripts/validate.sh"
echo "    markdownlint-cli2 \"**/*.md\" \"#node_modules\""
echo "    find . -name '*.sh' -not -path './node_modules/*' -print0 | xargs -0 shellcheck"
echo "    tessl skill lint skills/<skill-name>/"
