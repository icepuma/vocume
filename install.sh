#!/bin/bash
# Installs the latest Vocume release into /Applications.
#   curl -fsSL https://raw.githubusercontent.com/icepuma/vocume/main/install.sh | bash
# Downloading with curl doesn't set the quarantine flag, so the unsigned app opens without a Gatekeeper prompt.
# VOCUME_DMG=/path/to.dmg installs a local DMG instead (used for testing).
set -euo pipefail

tmp=$(mktemp -d)
trap 'hdiutil detach "$tmp/mnt" -quiet 2>/dev/null || true; rm -rf "$tmp"' EXIT

dmg="${VOCUME_DMG:-}"
if [[ -z "$dmg" ]]; then
  url=$(curl -fsSL https://api.github.com/repos/icepuma/vocume/releases/latest |
    grep -o '"browser_download_url": *"[^"]*\.dmg"' | head -1 | cut -d'"' -f4)
  [[ -n "$url" ]] || { echo "No Vocume release found." >&2; exit 1; }
  echo "Downloading $url"
  curl -fL --progress-bar "$url" -o "$tmp/Vocume.dmg"
  dmg="$tmp/Vocume.dmg"
fi

hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$tmp/mnt" -quiet
pkill -x Vocume 2>/dev/null || true
rm -rf /Applications/Vocume.app
cp -R "$tmp/mnt/Vocume.app" /Applications/
echo "Installed /Applications/Vocume.app"
open /Applications/Vocume.app
