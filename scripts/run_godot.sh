#!/usr/bin/env bash
# Locate the installed Godot binary and run it against this project.
# Usage: scripts/run_godot.sh [godot args...]   (no args -> launch project window)
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${GODOT_BIN:-$HOME/tools/godot/godot}"

if [ ! -x "$BIN" ]; then
  echo "Godot not found at $BIN — run scripts/install_godot.sh first" >&2
  exit 1
fi

exec "$BIN" --path "$PROJ_DIR" "$@"
