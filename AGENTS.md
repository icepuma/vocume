# Vocume

macOS menu-bar app (Swift package, macOS 15+) that annotates screenshots by hand or via the `claude` / `codex` CLIs.

## Scope and delivery

- Check `git status` first and preserve unrelated changes; never revert or reformat work you didn't make.
- Do what was asked, completely. Report adjacent issues as follow-ups unless they block the result; prefer a targeted edit over a rewrite.
- Work lands on `main` directly (a solo project; releases are cut from `main`). Commit or push only when asked.
- No users' data to migrate beyond `UserDefaults` settings and `.vocume` documents: favour clean design over compatibility shims, but don't silently drop a stored setting — read the old key once or say what resets — and keep opening documents already saved.

## Done means `make check` passes

`make check` runs what CI runs: strict `swift format` lint, build, Swift Testing suite. Run `make format` first; the `Makefile` has the other commands.

Match each claim to its evidence: `make check` proves it builds and the tests pass, not that the app behaves. For UI or AI behaviour, run it (`make run`) and say what you saw; for OCR, matching and redaction changes, measure on real captures before and after (Vocume keeps every capture in `$TMPDIR` as `Vocume <date>.png`) and report what was gained and lost. A test for a fix must fail without it. Vision-dependent tests are gated with `visionReadsText()` (CI's VM reads no text); fixtures go in `Tests/VocumeCoreTests/Fixtures`.

For material changes (OCR passes, matching, redaction, the AI prompt or schema, process handling), finish with a read-only adversarial review of the diff: concrete failure paths with evidence only, no style notes.

## Where code goes

- `Sources/VocumeCore` — everything testable: the `Mark` model (positions are 0–1 fractions of the image), geometry, `MarkRenderer`, OCR matching (`RecognizedScreenshot`), the AI prompt and reply parsing. New logic lands here, with tests in `Tests/VocumeCoreTests`.
- `Sources/Vocume` — the thin app: `App/` (menu bar, main menu, `Windows` coordinator), `Capture/` (`screencapture` modes, global shortcuts via Carbon hot keys), `Editor/`, `AI/` (CLI processes), `Settings/`. UI types are `@MainActor`; blocking CLI work runs off the main actor.

Every target is Swift 6 language mode with strict concurrency, on Swift 6.2+ (`isolated deinit`); CI runs on the `xcode-27` runner pinned to Xcode 27.0 (Swift 6.4), the same compiler as the Command Line Tools on our Macs: older compilers have crashed on valid code, so when the local toolchain moves, move CI with it.

## UI work

The editor's look is the "Light Table" world recorded in `DESIGN.md` (product context in `PRODUCT.md`); new UI follows its rules — one glass layer, accent means selection, the rainbow belongs to AI.

## Gotchas

- Run the app with `make run` (a signed `build/Vocume.app`), not `swift run`: permissions such as Screen Recording attach to the code signature, and the dev identity from `make signing` keeps it stable across builds. A bare binary or an ad-hoc build gets a new identity every time.
- Windows go through `Windows`: it switches the app to `.regular` while any editor/Settings window is open and back to `.accessory` after the last closes, and brings windows up with `NSApp.activate()` — only ever in response to a user action (cooperative activation).
- The logo's single source is `assets/vocume.svg`; `scripts/make-icon.sh` regenerates `Resources/AppIcon.icns` and the README PNG, and `LogoGlyph` draws the menu-bar template from the same path data.
- Builds must work with only the Command Line Tools, which lack the SwiftUI macro plugin: use `ObservableObject` + `@Published`, `@ObservedObject`, `@FocusState`; `@State`, `@Observable` and `#Preview` fail to compile there. Swift Testing macros work via the plugin path the `Makefile` adds.
- Every editor is a `.vocume` document (`VocumeDocument`: the image, marks, crop and undo/redo, a binary plist) in `CaptureLibrary`, `~/Library/Application Support/Vocume/Captures`. It saves a second after edits pause, on close and on quit, so closing never asks; documents untouched for 30 days are deleted at launch. Captures themselves still land in `$TMPDIR` first.
- Cropping is non-destructive: `EditorModel.crop` only limits what is shown and exported. Marks always stay in whole-image fractions, so a crop never remaps them; the AI asks for one with `crop` items, combined by `Mark.cropArea(of:)`.
- AI marks target text with `match` and are positioned by `RecognizedScreenshot.resolve`, which maps letters onto ink runs in the pixels. Vision's own sub-line boxes drift by a letter or two, so position from the line box plus pixels.
- "All X" requests (numbers, emails, secrets, red text…) never rely on the model listing items: it names a `TextKind` (`"detect"`), and the detectors in `Detectors.swift` find every occurrence. Redactions are then re-checked by `checkingRedactions` (paint the covers, OCR again, cover what is still found, up to three rounds). OCR runs 1×, 2× (or tiles), and 2× over small tiles turned dark-on-light (small text in coloured chips), all with a margin, in parallel, and merges the passes by text and confidence; see the doc comments before changing any of it, each choice was measured.
- AI providers are detected with each tool's own check (`claude auth status`, `codex login status`, Ollama's `/api/tags` + `/api/show` capabilities); parsing lives in `ProviderCheck`/`Ollama` in VocumeCore, user choices in `AISettings` (UserDefaults).
- Quality over speed: keep the user's configured model and reasoning effort and send full-resolution images. Speedups belong where they cost no quality (pre-warming the `claude` process, skipping MCP servers). Ollama is the measured exception: requests send `think: false`, since thinking made small local models 5–20× slower with no better marks.

## Commits

Conventional Commits with one scope and a lowercase subject: `feat(editor): resize handles on selected marks`, `fix(ocr): read small text in coloured chips`. Scopes: `core`, `ocr`, `ai`, `editor`, `capture`, `settings`, `app`, `ci`, `docs`, `release`. Breaking changes use `!` (`feat(ai)!: …`). The body says why, not what the diff shows. End with the attribution trailer the session asks for.

## Releasing

Semver from the commits since the last tag: any `feat` bumps the minor (0.x), only `fix`es bump the patch. Wait for CI on the commit to pass, then push an annotated `vX.Y.Z` tag on it; `.github/workflows/build.yml` builds the universal DMG with `scripts/build.sh` and publishes the release with generated notes. `install.sh` installs the latest release without a Gatekeeper prompt.

To install a release locally and keep Screen Recording permission, build the tag with the dev identity instead of installing the DMG: `git worktree add --detach <tmp> vX.Y.Z`, then `ARCHS=$(uname -m) DMG=0 VERSION=X.Y.Z scripts/build.sh` there, quit Vocume and `ditto` the app to `/Applications`.
