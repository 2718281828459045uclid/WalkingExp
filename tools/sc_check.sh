#!/usr/bin/env bash
# sc_check.sh — syntax check for SuperCollider files, in sclang batch mode.
#
# Compiles every code block of each .scd file without running it
# (tools/sc/check_syntax.scd) and reports blocks that do not compile.
# No server is booted and no sound is made.
#
# sclang notes, measured with SuperCollider 3.13.0:
#   - With stdin inherited from the calling shell, batch sclang did not
#     run the file; stdin comes from /dev/null here.
#   - sclang does not exit on its own after the file; check_syntax.scd
#     ends with "failures.exit". A perl alarm stops a hung run after
#     60 seconds.
#
# Usage: tools/sc_check.sh [file.scd ...]
#   files default to audio/supercollider/*.scd and tools/sc/*.scd

set -u
SCLANG="${SCLANG:-/Applications/SuperCollider.app/Contents/MacOS/sclang}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -x "$SCLANG" ]; then
  echo "skip  sclang not found at $SCLANG"
  exit 0
fi

files=("$@")
if [ ${#files[@]} -eq 0 ]; then
  files=("$ROOT"/audio/supercollider/*.scd "$ROOT"/tools/sc/*.scd)
fi

out="$(perl -e 'alarm shift; exec @ARGV' 60 "$SCLANG" "$ROOT/tools/sc/check_syntax.scd" "${files[@]}" </dev/null 2>&1)"
code=$?
grep -E "^(FAIL|checked|sc_check)|ERROR" <<<"$out" | sed "s#$ROOT/##"
if [ $code -eq 142 ]; then
  echo "FAIL  sclang did not finish within 60 s"
fi
exit $code
