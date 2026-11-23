#!/usr/bin/env bash
# light_perf.sh — cost and image of every lighting preset of the Lesson 18
# scene, windowed.
#
# Opens the Lesson 18 scene with vsync off, stops its scripts and physics,
# and draws four fixed views (start, face, far, gap) into an offscreen
# image of the given width (16:9). For each view and each preset of the
# scene's Lighting node it prints: 5th percentile, median and 95th
# percentile of the frame time, draw calls and triangles of the shadow pass
# and the main pass, and the quality probes (tools/godot/light_perf.gd).
# With an output directory it also saves one image per view and preset.
# A Godot window appears for several minutes
# (4 views x 15 presets x rounds x (frames + 90) frames).
#
# Usage: tools/light_perf.sh [frames per measurement] [rounds] [width] [output dir]
#        (defaults 300, 3, 2560, no images)

set -u
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$GODOT" --path "$ROOT/game" -s "$ROOT/tools/godot/light_perf.gd" -- "${1:-300}" "${2:-3}" "${3:-2560}" ${4:+"$4"} 2>&1 \
  | grep -E "^(driver|VoxelGI|GPU|view|#|[0-9]+ )|ERROR|^$"
