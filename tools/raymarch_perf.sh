#!/usr/bin/env bash
# raymarch_perf.sh — frame time of the Lesson 10 scene, windowed.
#
# Opens the Lesson 10 scene in a window with vsync off, places a camera at
# two fixed views, and prints the mean frame time with the raymarched
# formations hidden and with max_steps = 16, 32, 64, 96, 192.
# A Godot window appears for about half a minute.
#
# Usage: tools/raymarch_perf.sh [frames per measurement]   (default 240)

set -u
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$GODOT" --path "$ROOT/game" -s "$ROOT/tools/godot/raymarch_perf.gd" -- "${1:-240}" 2>&1 \
  | grep -E "^(view|overview|close)|ERROR"
