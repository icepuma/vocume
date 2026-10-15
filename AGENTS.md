# Vocume

macOS menu-bar app (Swift package, macOS 15+) that annotates screenshots by hand or via the `claude` / `codex` CLIs.

## Done means `make check` passes

`make check` runs what CI runs: strict `swift format` lint, build, Swift Testing suite. Run `make format` first; the `Makefile` has the other commands.

## Where code goes

- `Sources/VocumeCore` — everything testable: the `Mark` model (positions are 0–1 fractions of the image), geometry, `MarkRenderer`, OCR matching (`RecognizedScreenshot`), the AI prompt and reply parsing. New logic lands here, with tests in `Tests/VocumeCoreTests`.
- `Sources/Vocume` — the thin app: `App/` (menu bar, screenshot folder + clipboard watching), `Editor/` (model, view, AI overlay), `AI/` (CLI processes). UI types are `@MainActor`; blocking CLI work runs off the main actor.

Every target is Swift 6 language mode with strict concurrency, on Swift 6.2+ (`isolated deinit`); CI uses the `macos-26` runner to match.

## Gotchas

- Builds must work with only the Command Line Tools, which lack the SwiftUI macro plugin: use `ObservableObject` + `@Published`, `@ObservedObject`, `@FocusState`; `@State`, `@Observable` and `#Preview` fail to compile there. Swift Testing macros work via the plugin path the `Makefile` adds.
- AI marks target text with `match` and are positioned by `RecognizedScreenshot.resolve`, which maps letters onto ink runs in the pixels. Vision's own sub-line boxes drift by a letter or two, so position from the line box plus pixels.
- Quality over speed: keep the user's configured model and reasoning effort and send full-resolution images. Speedups belong where they cost no quality (pre-warming the `claude` process, skipping MCP servers).

## Releasing

Push a `vX.Y.Z` tag; `.github/workflows/build.yml` builds the universal DMG with `scripts/build.sh` and publishes the release. `install.sh` installs the latest release without a Gatekeeper prompt.
