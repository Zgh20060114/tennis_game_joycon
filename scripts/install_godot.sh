#!/usr/bin/env bash
# Download and install the latest (or given) Godot stable for Linux x86_64.
# Usage: scripts/install_godot.sh [VERSION_TAG]   e.g. scripts/install_godot.sh 4.7.2-stable
set -euo pipefail

GODOT_DIR="${GODOT_DIR:-$HOME/tools/godot}"
TAG="${1:-}"

if [ -z "$TAG" ]; then
  TAG=$(curl -fsSL https://api.github.com/repos/godotengine/godot/releases/latest \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['tag_name'])")
fi

BIN="$GODOT_DIR/godot"
if [ -x "$BIN" ] && "$BIN" --version 2>/dev/null | grep -q "${TAG%%-*}"; then
  echo "Godot $TAG already installed at $BIN"
  exit 0
fi

ASSET="Godot_v${TAG}_linux.x86_64.zip"
URL="https://github.com/godotengine/godot/releases/download/${TAG}/${ASSET}"
echo "Downloading $URL"
mkdir -p "$GODOT_DIR"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fSL --retry 3 -o "$TMP/$ASSET" "$URL"
unzip -o -q "$TMP/$ASSET" -d "$TMP"
EXTRACTED=$(find "$TMP" -name 'Godot_*_linux.x86_64' -type f | head -1)
mv "$EXTRACTED" "$BIN"
chmod +x "$BIN"
echo "Installed: $BIN ($("$BIN" --version))"
