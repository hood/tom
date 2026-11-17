#!/usr/bin/env bash
# Builds build/Tom.app (release, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/Tom.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Tom "$APP/Contents/MacOS/Tom"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null
echo "built $APP"
