#!/usr/bin/env bash
# render_check.sh — windowed render check.
#
# Opens each scene in a window for a few frames, saves a screenshot, and
# reports shader or script errors. Headless runs (tools/check.sh) catch
# shader compile errors but draw nothing and have no GPU device; use this
# script to inspect visual results and to exercise compute shaders.
#
# A Godot window appears for one to two seconds per scene.
#
# Usage: tools/render_check.sh [output_dir] [res://scene.tscn ...]
#   output_dir  defaults to ${TMPDIR}walkingexp_renders
#   scenes      default to scenes/sandbox.tscn and every scenes/lessons/*.tscn

set -u
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-${TMPDIR:-/tmp/}walkingexp_renders}"
shift || true
mkdir -p "$OUT"

scenes=("$@")
if [ ${#scenes[@]} -eq 0 ]; then
  for scene in "$ROOT"/game/scenes/sandbox.tscn "$ROOT"/game/scenes/lessons/*.tscn; do
    [ -f "$scene" ] && scenes+=("res://${scene#"$ROOT"/game/}")
  done
fi

failures=0
for rel in "${scenes[@]}"; do
  name="$(basename "$rel" .tscn)"
  out="$("$GODOT" --path "$ROOT/game" -s "$ROOT/tools/godot/capture.gd" -- "$rel" "$OUT/$name.png" 60 2>&1)"
  code=$?
  if [ $code -ne 0 ] || grep -q -E "SHADER ERROR|SCRIPT ERROR|^ERROR:" <<<"$out"; then
    echo "FAIL  $rel (exit $code)"
    grep -E "ERROR|error" <<<"$out" | head -20 | sed 's/^/      /'
    failures=$((failures + 1))
  else
    echo "ok    $rel -> $OUT/$name.png"
  fi
done

echo "---"
if [ $failures -eq 0 ]; then
  echo "all renders passed"
else
  echo "$failures render(s) failed"
fi
exit $failures
