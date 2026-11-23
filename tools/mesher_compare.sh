#!/usr/bin/env bash
# mesher_compare.sh — GPU versus CPU surface nets, with timings (Lesson 08).
#
# Opens a Godot window (a RenderingDevice exists only in windowed runs),
# samples a shape at each cell size, runs pass 1 of surface nets on the
# GPU and on the CPU, and prints sizes, timings and the largest
# differences. The window is blank and closes by itself.
#
# Usage: tools/mesher_compare.sh [shape.tres] [cell sizes ...]
#   shape   defaults to res://data/rocks/boulder_pile.tres
#   cells   default to 0.3 0.15 0.1

set -u
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHAPE="${1:-res://data/rocks/boulder_pile.tres}"
shift || true
CELLS=("$@")
[ ${#CELLS[@]} -eq 0 ] && CELLS=(0.3 0.15 0.1)

"$GODOT" --path "$ROOT/game" -s "$ROOT/tools/godot/mesher_compare.gd" -- "$SHAPE" "${CELLS[@]}" 2>&1 \
  | grep -v -E "^Godot Engine|^Vulkan|^Metal|^$"
