#!/usr/bin/env bash
# footsteps_nrt.sh — renders the footstep SynthDefs offline and checks them.
#
# Runs sclang in batch mode with tools/sc/footsteps_nrt.scd, which takes
# block 1 of audio/supercollider/05_footsteps.scd, renders 27 steps
# (3 surfaces x 3 impacts x 3 slopes) with scsynth in non-real-time mode
# to a WAV file, and prints peak and RMS per step. Nothing is played.
#
# Usage: tools/footsteps_nrt.sh [output.wav]   (default: a temporary file)

set -u
SCLANG="${SCLANG:-/Applications/SuperCollider.app/Contents/MacOS/sclang}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$(mktemp -t footsteps).wav}"

perl -e 'alarm shift; exec @ARGV' 120 "$SCLANG" "$ROOT/tools/sc/footsteps_nrt.scd" \
  "$ROOT/audio/supercollider/05_footsteps.scd" "$OUT" </dev/null 2>&1 | grep -E "^(STEP|RESULT)|ERROR"
code=${PIPESTATUS[0]}
exit $code
