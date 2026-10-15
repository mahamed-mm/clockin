#!/bin/zsh
# Builds Clockin/Sounds/focus-*.caf, the focus sounds: a tick-tock, brown
# noise, rain and a fireplace, each a seamless loop (rain and fire in two
# layers). Made here from scratch (scripts/make-focus-sounds.py), so there's
# nothing to license. IMA4 at 32 kHz keeps the set under 4 MB; the player
# decodes them once into memory.
set -euo pipefail
cd "${0:A:h}/.."
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
python3 -I scripts/make-focus-sounds.py "$t"
mkdir -p Clockin/Sounds
for wav in "$t"/focus-*.wav; do
  name=${wav:t:r}
  afconvert -f caff -d ima4 "$wav" "Clockin/Sounds/$name.caf"
done
du -ch Clockin/Sounds/focus-*.caf | tail -1
