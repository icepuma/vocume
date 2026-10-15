# Vocume

macOS menu-bar app (Swift package, macOS 15+) that annotates screenshots by hand or via the `claude` / `codex` CLIs.

## Done means `make check` passes

`make check` runs what CI runs: strict `swift format` lint, build, Swift Testing suite. Run `make format` first; the `Makefile` has the other commands.

## Where code goes

- `Sources/VocumeCore` — everything testable: the `Mark` model (positions are 0–1 fractions of the image), geometry, `MarkRenderer`, OCR matching (`RecognizedScreenshot`), the AI prompt and reply parsing. New logic lands here, with tests in `Tests/VocumeCoreTests`.
- `Sources/Vocume` — the thin app: `App/` (menu bar, main menu, `Windows` coordinator), `Capture/` (`screencapture` modes, global shortcuts via Carbon hot keys), `Editor/`, `AI/` (CLI processes), `Settings/`. UI types are `@MainActor`; blocking CLI work runs off the main actor.

Every target is Swift 6 language mode with strict concurrency, on Swift 6.2+ (`isolated deinit`); CI uses the `macos-26` runner to match.

## UI work

The editor's look is the "Light Table" world recorded in `DESIGN.md` (product context in `PRODUCT.md`); new UI follows its rules — one glass layer, accent means selection, the rainbow belongs to AI.

## Gotchas

- Run the app with `make run` (a signed `build/Vocume.app`), not `swift run`: permissions such as Screen Recording attach to the code signature, and the dev identity from `make signing` keeps it stable across builds. A bare binary or an ad-hoc build gets a new identity every time.

- Windows go through `Windows`: it switches the app to `.regular` while any editor/Settings window is open and back to `.accessory` after the last closes, and brings windows up with `NSApp.activate()` — only ever in response to a user action (cooperative activation).
- The logo's single source is `assets/vocume.svg`; `scripts/make-icon.sh` regenerates `Resources/AppIcon.icns` and the README PNG, and `LogoGlyph` draws the menu-bar template from the same path data.

- Builds must work with only the Command Line Tools, which lack the SwiftUI macro plugin: use `ObservableObject` + `@Published`, `@ObservedObject`, `@FocusState`; `@State`, `@Observable` and `#Preview` fail to compile there. Swift Testing macros work via the plugin path the `Makefile` adds.
- Cropping is non-destructive: `EditorModel.crop` only limits what is shown and exported. Marks always stay in whole-image fractions, so a crop never remaps them; the AI asks for one with `crop` items, combined by `Mark.cropArea(of:)`.
- AI marks target text with `match` and are positioned by `RecognizedScreenshot.resolve`, which maps letters onto ink runs in the pixels. Vision's own sub-line boxes drift by a letter or two, so position from the line box plus pixels.
- AI providers are detected with each tool's own check (`claude auth status`, `codex login status`, Ollama's `/api/tags` + `/api/show` capabilities); parsing lives in `ProviderCheck`/`Ollama` in VocumeCore, user choices in `AISettings` (UserDefaults).
- Quality over speed: keep the user's configured model and reasoning effort and send full-resolution images. Speedups belong where they cost no quality (pre-warming the `claude` process, skipping MCP servers). Ollama is the measured exception: requests send `think: false`, since thinking made small local models 5–20× slower with no better marks.

## Releasing

Push a `vX.Y.Z` tag; `.github/workflows/build.yml` builds the universal DMG with `scripts/build.sh` and publishes the release. `install.sh` installs the latest release without a Gatekeeper prompt.
