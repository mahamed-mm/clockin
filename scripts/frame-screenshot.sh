#!/bin/zsh
# Puts a simulator screenshot in the README's phone frame (694x1351, or
# 1351x694 for a landscape shot): rim #5A5048, bezel #14110F and a soft
# brown shadow on transparency. Capture with the display mask so the
# corners and the Dynamic Island come out right:
#   xcrun simctl io <device> screenshot --mask=alpha shot.png
#   scripts/frame-screenshot.sh shot.png docs/screenshots/name.png
set -euo pipefail
in=$1; out=$2
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT

# Landscape shots are framed upright, then turned back.
landscape=$(magick identify -format '%[fx:w>h]' "$in")
if [[ $landscape == 1 ]]; then magick "$in" -rotate 90 "$t/in.png"; else cp "$in" "$t/in.png"; fi

magick "$t/in.png" -resize 560x "$t/screen.png"
h=$(magick identify -format %h "$t/screen.png")
bw=594; bh=$((h + 34))
magick -size ${bw}x${bh} xc:none -fill '#5A5048' -draw "roundrectangle 0,0 $((bw-1)),$((bh-1)) 94,94" \
  -fill '#14110F' -draw "roundrectangle 4,4 $((bw-5)),$((bh-5)) 90,90" "$t/body.png"
magick "$t/screen.png" \( -size 560x${h} xc:none -fill white -draw "roundrectangle 0,0 559,$((h-1)) 76,76" \) \
  -compose DstIn -composite "$t/rounded.png"
magick "$t/body.png" "$t/rounded.png" -geometry +17+17 -compose Over -composite "$t/phone.png"
magick -size 694x1351 xc:none \
  \( "$t/body.png" -background 'rgb(58,42,28)' -shadow 40x22+0+18 \) -geometry +6-10 -compose Over -composite \
  "$t/phone.png" -geometry +50+34 -compose Over -composite "$t/framed.png"

if [[ $landscape == 1 ]]; then magick "$t/framed.png" -rotate -90 "$out"; else cp "$t/framed.png" "$out"; fi
