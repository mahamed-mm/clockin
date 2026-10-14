#!/bin/zsh
# Draws Tick on the Mac from the same SwiftUI code the app uses:
#   scripts/render-tick.sh sheet out.png   every pose at several sizes
#   scripts/render-tick.sh shapes out.png  every pose as a solid 60 pt silhouette
#   scripts/render-tick.sh icon dir        the app icon's layers
set -euo pipefail
cd "${0:A:h}/.."
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
xcrun swiftc -parse-as-library -O Shared/Mascot/*.swift scripts/render-tick.swift -o "$t/render-tick"
"$t/render-tick" "$@"
