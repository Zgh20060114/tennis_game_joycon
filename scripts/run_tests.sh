#!/usr/bin/env bash
# Run every headless test script and fail if any fails.
set -uo pipefail

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0

for test_script in "$PROJ_DIR"/tests/test_*.gd; do
  [ -e "$test_script" ] || { echo "no test scripts found"; exit 1; }
  echo "=== $(basename "$test_script") ==="
  "$PROJ_DIR/scripts/run_godot.sh" --headless --script "tests/$(basename "$test_script")"
  if [ $? -ne 0 ]; then failed=1; fi
done

if [ $failed -ne 0 ]; then
  echo "TESTS FAILED"
  exit 1
fi
echo "ALL TESTS PASSED"
