#!/usr/bin/env bash
set -euo pipefail

# agymg Installer
# Supports two modes:
#   1. Local repo mode: ./Scripts/install.sh (when invoked inside a cloned repository)
#   2. Remote 1-liner:  curl -fsSL https://raw.githubusercontent.com/stankela16/agymg/v1.0.1/Scripts/install.sh | bash

REPO_URL="${AGYMG_REPO_URL:-https://github.com/stankela16/agymg.git}"
REF="${AGYMG_REF:-v1.0.1}"

if ! command -v swift >/dev/null 2>&1; then
  echo "Error: Swift toolchain not found. Install Xcode 16+ or Xcode Command Line Tools 16+ first:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

SWIFT_MAJOR="$(swift --version 2>&1 | sed -nE 's/.*Swift version ([0-9]+)\..*/\1/p' | head -n 1)"
if [[ -z "$SWIFT_MAJOR" || "$SWIFT_MAJOR" -lt 6 ]]; then
  echo "Error: Swift 6.0+ (Xcode 16+ / Command Line Tools 16+) is required." >&2
  echo "Detected: $(swift --version 2>&1 | head -n 1)" >&2
  exit 1
fi

SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

CLEANUP_TMP=""
cleanup() {
  if [[ -n "$CLEANUP_TMP" && -d "$CLEANUP_TMP" ]]; then
    rm -rf "$CLEANUP_TMP"
  fi
}
trap cleanup EXIT

if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/../Package.swift" && -f "$SCRIPT_DIR/package_app.sh" ]]; then
  WORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  echo "==> Using local checkout at $WORK_ROOT"
else
  if ! command -v git >/dev/null 2>&1; then
    echo "Error: git not found. Install Xcode Command Line Tools first: xcode-select --install" >&2
    exit 1
  fi
  CLEANUP_TMP="$(mktemp -d -t agymg_install)"
  WORK_ROOT="$CLEANUP_TMP/agymg"
  echo "==> Cloning $REPO_URL ($REF)..."
  git -c advice.detachedHead=false clone --depth 1 --branch "$REF" "$REPO_URL" "$WORK_ROOT"
fi

cd "$WORK_ROOT"

echo "==> Building and signing agymg.app (release)..."
./Scripts/package_app.sh release

if [[ -n "${AGYMG_APP_DEST:-}" ]]; then
  DEST_APPS_DIR="$AGYMG_APP_DEST"
elif [[ -w "/Applications" ]]; then
  DEST_APPS_DIR="/Applications"
else
  DEST_APPS_DIR="$HOME/Applications"
fi

mkdir -p "$DEST_APPS_DIR"
DEST_APP="$DEST_APPS_DIR/agymg.app"

echo "==> Installing app bundle to $DEST_APP..."
WAS_RUNNING=0
if pgrep -f "$DEST_APP/Contents/MacOS/agymg" >/dev/null 2>&1; then
  WAS_RUNNING=1
  pkill -f "$DEST_APP/Contents/MacOS/agymg" 2>/dev/null || true
  sleep 0.3
fi
rm -rf "$DEST_APP"
ditto "$WORK_ROOT/agymg.app" "$DEST_APP"
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true
rm -rf "$WORK_ROOT/agymg.app" "$WORK_ROOT/agymg.zip"

is_brew_cellar_link() {
  local target_path="$1"
  if [[ -L "$target_path" ]]; then
    local resolved
    resolved="$(readlink "$target_path" 2>/dev/null || true)"
    if [[ "$resolved" == *"Cellar/agymg"* ]]; then
      return 0
    fi
  fi
  return 1
}

# Link CLI binary into PATH without clobbering a Homebrew Cellar formula link
BIN_TARGET=""
if [[ -n "${AGYMG_BIN_DIR:-}" ]]; then
  mkdir -p "$AGYMG_BIN_DIR"
  BIN_TARGET="$AGYMG_BIN_DIR/agymg"
elif [[ -L "/opt/homebrew/bin/agymg" && -w "/opt/homebrew/bin" ]] && ! is_brew_cellar_link "/opt/homebrew/bin/agymg"; then
  BIN_TARGET="/opt/homebrew/bin/agymg"
elif [[ -L "/usr/local/bin/agymg" && -w "/usr/local/bin" ]] && ! is_brew_cellar_link "/usr/local/bin/agymg"; then
  BIN_TARGET="/usr/local/bin/agymg"
elif [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
  mkdir -p "$HOME/.local/bin"
  BIN_TARGET="$HOME/.local/bin/agymg"
elif [[ -d "/opt/homebrew/bin" && -w "/opt/homebrew/bin" ]] && ! is_brew_cellar_link "/opt/homebrew/bin/agymg"; then
  BIN_TARGET="/opt/homebrew/bin/agymg"
elif [[ -d "/usr/local/bin" && -w "/usr/local/bin" ]] && ! is_brew_cellar_link "/usr/local/bin/agymg"; then
  BIN_TARGET="/usr/local/bin/agymg"
else
  mkdir -p "$HOME/.local/bin"
  BIN_TARGET="$HOME/.local/bin/agymg"
fi

ln -sf "$DEST_APP/Contents/MacOS/agymg" "$BIN_TARGET"
echo "==> Linked CLI binary: $BIN_TARGET -> $DEST_APP/Contents/MacOS/agymg"

echo ""
echo "✓ agymg installed successfully!"
echo "  • App: $DEST_APP"
echo "  • CLI: $BIN_TARGET"
echo ""
if [[ "$WAS_RUNNING" == "1" ]]; then
  open "$DEST_APP"
  echo "==> Relaunched $DEST_APP"
else
  echo "Launch with: open \"$DEST_APP\""
fi
if [[ "$BIN_TARGET" == "$HOME/.local/bin/agymg" ]] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  echo "Note: Add ~/.local/bin to your PATH to run 'agymg' from any terminal:"
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi
