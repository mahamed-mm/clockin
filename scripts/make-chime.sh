#!/bin/zsh
# Builds Clockin/Sounds/clockin-ding.caf, the chime the end alarm and the
# end notification play. Made here from scratch (scripts/make-chime.py),
# so there's nothing to license. IMA4 keeps the 24-second file small.
set -euo pipefail
cd "${0:A:h}/.."
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
python3 -I scripts/make-chime.py "$t/chime.wav"
mkdir -p Clockin/Sounds
afconvert -f caff -d ima4 "$t/chime.wav" Clockin/Sounds/clockin-ding.caf
afinfo Clockin/Sounds/clockin-ding.caf | grep -E "duration|format"
