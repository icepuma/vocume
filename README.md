<p align="center"><img src="assets/vocume.svg" width="128" height="128" alt="Vocume logo"></p>

# Vocume

A macOS menu-bar app for annotating screenshots — by hand, or by asking Claude or Codex.

Capture with Vocume's shortcuts or menu and it opens in an editor: arrows, boxes, highlights, solid redaction, pen, text and numbered steps. Or type what you want ("redact every email address", "point out the UI bugs") and Claude or Codex marks it up for you, using on-device text recognition to hit exact words and letters. Copy (⇧⌘C) or save (⌘S) the result.

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

Vocume works with what you already have — no API keys:

- **Claude** — the `claude` CLI ([Claude Code](https://claude.com/claude-code)), signed in with your subscription.
- **Codex** — the `codex` CLI, signed in with ChatGPT.
- **Ollama** — a vision model running locally ([ollama.com](https://ollama.com)), e.g. `ollama pull qwen2.5vl`.

Open **Settings…** (⌘, from the menu-bar icon) to see what was detected on your Mac, choose which providers to offer, pick the Ollama model, or turn AI off entirely (the AI bar disappears).

## Usage

Vocume lives in the menu bar. Capture with a shortcut or from its menu, and the screenshot opens in the editor:

| Capture | Default shortcut |
|---|---|
| Area (Space switches to window mode, Esc cancels) | ⌥⇧⌘4 |
| Window | ⌥⇧⌘W |
| Entire screen (the one under the pointer) | ⌥⇧⌘3 |
| Entire screen in 5 seconds | menu only |

Change or clear the shortcuts in **Settings…** (⌘,). The menu also has **Open Image…** and **Annotate Clipboard Image** for images you already have.

In the editor:

- Tools: **V** select · **A** arrow · **R** box · **H** highlight · **X** redact · **P** pen · **T** text · **N** step; colour and size under **Ink**.
- ⌘Z undo, ⌫ delete, Esc deselect; ⇧⌘C copies the annotated image, ⌘S saves it. Closing with uncopied, unsaved marks asks first.
- While an editor is open Vocume shows in the Dock and ⌘-Tab; closing the last one returns it to the menu bar.

## Build from source

```bash
make signing              # once: a stable local signing identity (see below)
make run                  # build build/Vocume.app for this Mac and launch it
make check                # lint, build and test (what CI runs)
VERSION=0.1.0 make dmg    # → build/Vocume.app and build/Vocume-0.1.0.dmg
```

**Permissions survive rebuilds.** macOS ties privacy permissions such as Screen Recording to an app's code signature. `make signing` creates a self-signed "Vocume Local Development" identity in its own keychain (`~/Library/Application Support/dev.icepuma.vocume/`; no trust settings changed), and every local build is signed with it, so you grant a permission once. Without it builds are ad-hoc signed and each one looks like a new app. Remove it with `scripts/dev-signing.sh --remove`.

Needs only the Xcode Command Line Tools with Swift 6.2 or later (`xcode-select --install`). Contributor notes are in [AGENTS.md](AGENTS.md).

## Releasing

Push a tag; GitHub Actions builds the DMG and publishes the release:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

To ship signed and notarized builds (no Gatekeeper warning), add these repository secrets: `MACOS_CERT_P12` (base64 of a Developer ID Application certificate), `MACOS_CERT_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID` and `APPLE_APP_PASSWORD`.
