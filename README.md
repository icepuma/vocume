# Vocume

A macOS menu-bar app for annotating screenshots — by hand, or by asking Claude or Codex.

Take a screenshot and Vocume opens it in an editor: arrows, boxes, highlights, solid redaction, pen, text and numbered steps. Or type what you want ("redact every email address", "point out the UI bugs") and Claude or Codex marks it up for you, using on-device text recognition to hit exact words and letters. Copy (⇧⌘C) or save (⌘S) the result.

*Named after the Goa'uld vo'cume from Stargate SG-1 — a device that records what it sees and plays it back.*

## Install

Quickest — installs the latest release into `/Applications` with no Gatekeeper prompt:

```bash
curl -fsSL https://raw.githubusercontent.com/icepuma/vocume/main/install.sh | bash
```

Or by hand:

1. Download the latest `Vocume-x.y.z.dmg` from [Releases](https://github.com/icepuma/vocume/releases).
2. Open it and drag **Vocume** onto **Applications**.
3. First launch: if macOS says it can't verify the app, open **System Settings → Privacy & Security** and click **Open Anyway** (only needed for builds that aren't notarized).

Requires macOS 15 or later.

## AI annotation

Vocume uses the `claude` ([Claude Code](https://claude.com/claude-code)) or `codex` CLI you already have installed and logged in — your subscription, no API keys. Install at least one and sign in once in a terminal.

## Usage

- Screenshots saved to your screenshot folder or copied to the clipboard (⌃⌘⇧4) open automatically.
- Tools: **V** select · **A** arrow · **R** box · **H** highlight · **X** redact · **P** pen · **T** text · **N** step. ⌘Z undo, ⌫ delete, Esc deselect.
- Menu-bar icon → **Open Image…** to annotate any PNG or JPEG.

## Build from source

```bash
make run                  # build and launch
make check                # lint, build and test (what CI runs)
VERSION=0.1.0 make dmg    # → build/Vocume.app and build/Vocume-0.1.0.dmg
```

Needs only the Xcode Command Line Tools (`xcode-select --install`). Contributor notes are in [AGENTS.md](AGENTS.md).

## Releasing

Push a tag; GitHub Actions builds the DMG and publishes the release:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

To ship signed and notarized builds (no Gatekeeper warning), add these repository secrets: `MACOS_CERT_P12` (base64 of a Developer ID Application certificate), `MACOS_CERT_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID` and `APPLE_APP_PASSWORD`.
