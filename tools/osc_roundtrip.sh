#!/usr/bin/env bash
# osc_roundtrip.sh — sends OSC from Godot to sclang and checks what arrives.
#
#   1. Starts sclang in the background with tools/sc/osc_roundtrip_listener.scd.
#      It prints "PORT <n>": 57120, or 57121 if another sclang (the IDE)
#      holds 57120.
#   2. Runs Godot with tools/godot/osc_send.gd, which sends three messages
#      through OscSender to that port.
#   3. Waits for sclang, which exits 0 if every message arrived with the
#      expected values.
# No SuperCollider server is booted; nothing is played.
#
# Usage: tools/osc_roundtrip.sh

set -u
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
SCLANG="${SCLANG:-/Applications/SuperCollider.app/Contents/MacOS/sclang}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$(mktemp -t osc_roundtrip)"

# sclang gets stdin from /dev/null (see sc_check.sh) and at most 30 s.
perl -e 'alarm shift; exec @ARGV' 30 "$SCLANG" "$ROOT/tools/sc/osc_roundtrip_listener.scd" </dev/null >"$LOG" 2>&1 &
sc_pid=$!

# Wait up to 20 s for the PORT line (class library compile takes about 1 s).
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

"$GODOT" --headless --path "$ROOT/game" -s "$ROOT/tools/godot/osc_send.gd" -- "$port" 2>&1 | grep "^sent"
wait $sc_pid
code=$?
grep -E "^(PORT|RECV|RESULT|TIMEOUT)" "$LOG"
rm -f "$LOG"
if [ $code -eq 0 ]; then echo "ok    round trip"; else echo "FAIL  round trip (sclang exit $code)"; fi
exit $code
