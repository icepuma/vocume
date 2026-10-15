#!/bin/bash
# Builds build/Vocume.app (universal: Apple silicon + Intel) and build/Vocume-<version>.dmg.
#   VERSION=1.2.3 scripts/build.sh
#   ARCHS=arm64 DMG=0 scripts/build.sh      # quick local app (what `make app` does)
# Signing, first match wins:
#   SIGN_IDENTITY="Developer ID Application: …" (+ NOTARY_PROFILE, a `notarytool store-credentials`
#     profile) signs, notarizes and staples — CI does that when the matching secrets exist.
#   The local dev identity from scripts/dev-signing.sh — stable across builds, so macOS keeps
#     privacy permissions such as Screen Recording.
#   Otherwise ad-hoc: runs, but every build is a new app to macOS (permissions reset).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.0.0-dev}"
ARCHS="${ARCHS:-arm64 x86_64}"
DMG="${DMG:-1}"
MIN_MACOS=15.0
APP=build/Vocume.app

rm -rf build && mkdir -p "$APP/Contents/MacOS"

binaries=()
for arch in $ARCHS; do
  # Separate scratch paths: some SwiftPM versions put every triple's product in the same folder.
  args=(-c release --product Vocume --triple "$arch-apple-macosx$MIN_MACOS" --scratch-path ".build/$arch")
  swift build "${args[@]}"
  binaries+=("$(swift build "${args[@]}" --show-bin-path)/Vocume")
done
lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/Vocume"

cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources" && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
plutil -replace CFBundleShortVersionString -string "${VERSION%%-*}" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
elif scripts/dev-signing.sh --check; then
  scripts/dev-signing.sh --sign "$APP"
else
  codesign --force --sign - "$APP"
  echo "note: ad-hoc signed; run scripts/dev-signing.sh once so permissions survive rebuilds" >&2
fi

if [[ "$DMG" == 0 ]]; then
  echo "Built $APP"
  exit 0
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
