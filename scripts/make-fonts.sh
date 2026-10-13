#!/bin/zsh
# Rebuilds Shared/Fonts from the Fraunces variable font (SIL OFL 1.1), pinned
# to one google/fonts commit and checked by hash. Needs python3; fontTools
# goes into a throwaway virtual environment. The built fonts are committed,
# so this only runs when the cuts in make-fonts.py change.
set -euo pipefail
cd "${0:A:h}/.."

commit=ac502d8eff76ef4d9477cdcc8ef7d0c84fde5372
sha=177ff6c0f14e5550a3c624247cd1189611d4eb65d000b14944c63d967958abbb
base="https://raw.githubusercontent.com/google/fonts/$commit/ofl/fraunces"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/src"

curl -sfL -o "$work/src/Fraunces.ttf" "$base/Fraunces%5BSOFT,WONK,opsz,wght%5D.ttf"
echo "$sha  $work/src/Fraunces.ttf" | shasum -a 256 -c --quiet
curl -sfL -o Shared/Fonts/OFL.txt "$base/OFL.txt"

python3 -m venv "$work/venv"
"$work/venv/bin/pip" install --quiet fonttools==4.66.1
"$work/venv/bin/python" -I scripts/make-fonts.py "$work/src/Fraunces.ttf" Shared/Fonts
