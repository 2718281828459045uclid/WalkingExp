#!/usr/bin/env bash
# footstep_timing.sh — measures footstep timing between Godot and sclang.
#
#   1. Starts sclang in the background with
#      tools/sc/footstep_timing_listener.scd, which prints "PORT <n>".
#   2. Runs Godot with tools/godot/walk_steps.gd: the Lesson 05 scene,
#      walking forward, sending /foot/step to that port.
#   3. sclang prints the spread of arrival intervals, of time tag
#      intervals, and of the margin (tag - arrival), then exits.
# No SuperCollider server is booted; nothing is played.
#
# Usage: tools/footstep_timing.sh [seconds] [immediate|tagged] [latency ms] [--window]
#   --window runs Godot with a window (real frame timing) instead of headless.

set -u
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
SCLANG="${SCLANG:-/Applications/SuperCollider.app/Contents/MacOS/sclang}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$(mktemp -t footstep_timing)"

display="--headless"
args=()
for a in "$@"; do
  if [ "$a" = "--window" ]; then display=""; else args+=("$a"); fi
done
seconds="${args[0]:-6}"
mode="${args[1]:-tagged}"
latency="${args[2]:-50}"

perl -e 'alarm shift; exec @ARGV' 60 "$SCLANG" "$ROOT/tools/sc/footstep_timing_listener.scd" </dev/null >"$LOG" 2>&1 &
sc_pid=$!

port=""
for i in $(seq 1 200); do
  port="$(sed -n 's/^PORT \([0-9]*\)$/\1/p' "$LOG")"
  [ -n "$port" ] && break
  sleep 0.1
done
if [ -z "$port" ]; then
  echo "FAIL  sclang did not report a port"
  cat "$LOG"
  exit 1
fi

perl -e 'alarm shift; exec @ARGV' 60 "$GODOT" $display --path "$ROOT/game" -s "$ROOT/tools/godot/walk_steps.gd" -- "$port" "$seconds" "$mode" "$latency" 2>&1 | grep -E "^sent|ERROR"
wait $sc_pid
code=$?
grep -E "^(PORT|STEPS|ARRIVAL|TAG|JITTER|MARGIN|LATE|TIMEOUT)" "$LOG"
rm -f "$LOG"
exit $code
