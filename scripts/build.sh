#!/bin/bash
# Builds build/FinderTweaks.app. Signs with the local "FinderTweaks Local Signing" identity when it
# exists (`make cert`), so macOS keeps the Accessibility/Automation grants across rebuilds;
# otherwise falls back to an ad-hoc signature and the grants reset on every build.
set -euo pipefail
cd "$(dirname "$0")/.."
IDENTITY="FinderTweaks Local Signing"
APP=build/FinderTweaks.app

swift build -c release
BIN="$(swift build -c release --show-bin-path)/FinderTweaks"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/FinderTweaks"

if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "warning: no '$IDENTITY' identity (run: make cert); signing ad-hoc" >&2
  codesign --force --sign - "$APP"
fi
echo "built $APP"
