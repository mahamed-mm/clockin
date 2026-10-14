#!/bin/zsh
# Adds strings found by the last build to Shared/Localizable.xcstrings and
# marks strings no longer in the code as stale. Xcode does this when it
# builds; command-line builds don't, so run this after `xcodebuild build`,
# passing the build's derived data folder if it isn't the default one.
# Every .stringsdata file needs its own --stringsdata (given once, the rest
# are read as catalogs and nothing changes), and all of them must be passed,
# or strings still in use are marked stale.
set -euo pipefail
cd "${0:A:h}/.."
if [[ $# -gt 0 ]]; then
  root="$1/Build/Intermediates.noindex"
else
  root=$(xcodebuild -project Clockin.xcodeproj -scheme Clockin -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ OBJROOT /{print $2; exit}')
fi
args=()
for f in $(find "$root" -name '*.stringsdata' -path '*Debug-iphonesimulator*' -not -path '*ClockinTests*'); do
  args+=(--stringsdata "$f")
done
(( ${#args} )) || { echo "No .stringsdata under $root; build first." >&2; exit 1; }
xcrun xcstringstool sync Shared/Localizable.xcstrings "${args[@]}"
