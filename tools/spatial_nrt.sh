#!/usr/bin/env bash
# spatial_nrt.sh — measures the Lesson 06 spatializer and ambience offline.
#
# Runs sclang in batch mode with tools/sc/spatial_nrt.scd, which takes
# block 1 of audio/supercollider/06_spatial_audio.scd, renders probe
# sounds at several directions, elevations, and distances, and the
# ambience SynthDefs, with scsynth in non-real-time mode to a WAV file.
# Prints the level per loudspeaker channel for each case. Nothing is
# played.
#
# Usage: tools/spatial_nrt.sh [speakers] [output.wav]
#   speakers   output channels of the ring (default 2)
#   output     default: a temporary file

set -u
SCLANG="${SCLANG:-/Applications/SuperCollider.app/Contents/MacOS/sclang}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEAKERS="${1:-2}"
OUT="${2:-$(mktemp -t spatial).wav}"

perl -e 'alarm shift; exec @ARGV' 300 "$SCLANG" "$ROOT/tools/sc/spatial_nrt.scd" \
  "$ROOT/audio/supercollider/06_spatial_audio.scd" "$OUT" "$SPEAKERS" </dev/null 2>&1 | grep -E "^(DIR|ELEV|DIST|SOURCE|RESULT)|ERROR"
code=${PIPESTATUS[0]}
exit $code
