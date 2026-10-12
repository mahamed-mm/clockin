#!/bin/zsh
# Adds strings found by the last build to Shared/Localizable.xcstrings and
# marks strings no longer in the code as stale. Xcode does this when it
# builds; command-line builds don't, so run this after `xcodebuild build`.
set -euo pipefail
cd "${0:A:h}/.."
objroot=$(xcodebuild -project Clockin.xcodeproj -scheme Clockin -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ OBJROOT /{print $2; exit}')
files=("${(@f)$(find "$objroot" -name '*.stringsdata' -path '*-iphonesimulator/Clockin*.build/*' \
  -not -path '*ClockinTests*')}")
xcrun xcstringstool sync Shared/Localizable.xcstrings --stringsdata "${files[@]}"
