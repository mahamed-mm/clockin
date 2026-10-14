#!/bin/zsh
# Draws Tick on the Mac from the same SwiftUI code the app uses:
#   scripts/render-tick.sh sheet out.png   every pose at several sizes
#   scripts/render-tick.sh shapes out.png  every pose as a solid 60 pt silhouette
#   scripts/render-tick.sh icon dir        the app icon's layers
set -euo pipefail
cd "${0:A:h}/.."
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
# Tick's colours come from the app's asset catalog, compiled into a bundle.
mkdir -p "$t/Assets.bundle/Contents/Resources"
plutil -create xml1 "$t/Assets.bundle/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string com.moha.clockin.render-tick "$t/Assets.bundle/Contents/Info.plist"
xcrun actool Clockin/Assets.xcassets --compile "$t/Assets.bundle/Contents/Resources" --platform macosx \
    --minimum-deployment-target 14.0 --output-partial-info-plist "$t/assets.plist" > /dev/null
xcrun swiftc -parse-as-library -O Shared/Mascot/**/*.swift scripts/render-tick.swift -o "$t/render-tick"
TICK_ASSETS="$t/Assets.bundle" "$t/render-tick" "$@"
