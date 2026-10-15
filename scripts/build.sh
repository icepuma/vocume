#!/bin/bash
# Builds build/Vocume.app (universal: Apple silicon + Intel) and build/Vocume-<version>.dmg.
#   VERSION=1.2.3 scripts/build.sh
# Signing: with no SIGN_IDENTITY the app is ad-hoc signed (runs, but Gatekeeper warns on first open).
# Set SIGN_IDENTITY="Developer ID Application: …" and NOTARY_PROFILE (a `notarytool store-credentials`
# profile) to sign, notarize and staple — CI does that when the matching secrets exist.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.0.0-dev}"
MIN_MACOS=15.0
APP=build/Vocume.app

rm -rf build && mkdir -p "$APP/Contents/MacOS"

for arch in arm64 x86_64; do
  swiftc -parse-as-library -O -target "$arch-apple-macos$MIN_MACOS" Vocume.swift -o "build/Vocume-$arch"
done
lipo -create build/Vocume-arm64 build/Vocume-x86_64 -output "$APP/Contents/MacOS/Vocume"
rm build/Vocume-arm64 build/Vocume-x86_64

cp Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "${VERSION%%-*}" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi

# DMG with the app and an Applications shortcut to drag it onto.
mkdir build/dmg && cp -R "$APP" build/dmg/ && ln -s /Applications build/dmg/Applications
DMG="build/Vocume-$VERSION.dmg"
hdiutil create -volname Vocume -srcfolder build/dmg -fs HFS+ -format UDZO -ov "$DMG"
rm -rf build/dmg

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  fi
fi

echo "Built $DMG"
