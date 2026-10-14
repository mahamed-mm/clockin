#!/bin/zsh
# Builds Clockin/Sounds/timer-*.caf, the kitchen-timer sounds: the dial's
# ratchet, the wind-up on Start, and the Pause and Resume clicks. Made here
# from scratch (scripts/make-sounds.py), so there's nothing to license.
# 16-bit linear PCM, which system sounds play with the least delay.
set -euo pipefail
cd "${0:A:h}/.."
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
python3 -I scripts/make-sounds.py "$t"
mkdir -p Clockin/Sounds
for wav in "$t"/timer-*.wav; do
  name=${wav:t:r}
  afconvert -f caff -d LEI16 "$wav" "Clockin/Sounds/$name.caf"
  afinfo "Clockin/Sounds/$name.caf" | grep -E "estimated duration" | sed "s/^/$name: /"
done
