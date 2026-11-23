#!/usr/bin/env bash
# check.sh — headless regression check for the Godot project.
#
# Runs every lesson scene for a fixed number of frames, then every test
# script in game/tests/. Fails if Godot prints an error or a test exits
# with a nonzero code.
#
# Headless Godot uses a dummy renderer. In Godot 4.6 it still parses
# shaders and reports compile errors, but it draws nothing and has no GPU:
# visual results and compute shaders need a windowed run
# (tools/render_check.sh).
#
# Usage: tools/check.sh [frames]        (default 120 frames per scene)

set -u
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRAMES="${1:-120}"
failures=0

# Runs Godot with the given arguments and reports ok or FAIL under a label.
run() {
  local label="$1"; shift
  local out code
  out="$("$GODOT" --headless --path "$ROOT/game" "$@" 2>&1)"
  code=$?
  if [ $code -ne 0 ] || grep -q -E "SCRIPT ERROR|SHADER ERROR|^ERROR:|Parse Error" <<<"$out"; then
    echo "FAIL  $label (exit $code)"
    grep -E "ERROR|FAIL|at: " <<<"$out" | head -20 | sed 's/^/      /'
    failures=$((failures + 1))
  else
    echo "ok    $label"
  fi
}

# Import new or changed assets once, so the runs below do not import in parallel.
"$GODOT" --headless --path "$ROOT/game" --import >/dev/null 2>&1

for scene in "$ROOT"/game/scenes/sandbox.tscn "$ROOT"/game/scenes/lessons/*.tscn; do
  [ -f "$scene" ] || continue
  rel="res://${scene#"$ROOT"/game/}"
  run "scene $rel" "$rel" --quit-after "$FRAMES"
done

for test in "$ROOT"/game/tests/test_*.gd; do
  [ -f "$test" ] || continue
  rel="res://${test#"$ROOT"/game/}"
  run "test  $rel" -s "$rel"
done

echo "---"
if [ $failures -eq 0 ]; then
  echo "all checks passed"
else
  echo "$failures check(s) failed"
fi
exit $failures
