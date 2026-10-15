---
version: 1
slug: "sources-vocume-editor-editorview-swift"
primary_target: "Sources/Vocume/Editor/EditorView.swift"
related_targets: ["Sources/Vocume/Editor/ThinkingOverlay.swift"]
---

# Editor window

Scope: the annotation editor window (tools, canvas, AI prompt, export). Mode: Operate.
Task: mark up a fresh screenshot by hand or by AI request, then copy or save it. Frequent, short sessions that interrupt other work.
Constraints: macOS 15+, native SwiftUI in AppKit windows, no SwiftUI macros (CLT builds); Liquid Glass only behind `#available(macOS 26, *)`.

## Direction contract

THESIS: The screenshot is a print laid on a lit table; tools rest at the table's edge and disappear into the task. Refuses the category default of a dense Preview-style toolbar strip.

OWN-WORLD: Graphite table surround (system under-page grey in Dark Mode; a lighter #CFCFD1 table in Light Mode), the print with a soft lift shadow and hairline edge, exactly one glass layer above it (never glass on glass), system accent for selection, mark colours as grease-pencil inks shown on tool tips. SF Symbols, system font; monospaced rainbow only for AI progress.

STORY: The user sees their screenshot immediately, picks a pen, marks, and copies. When they'd rather describe it, they ask the capsule; progress is unmistakable and blocks new requests (the capsule becomes the progress strip with Cancel/Esc), while the canvas stays editable — the user asked only for the input to be blocked, and the HIG research favours not freezing the window. AI marks land as ordinary marks in one undo step.

FIRST VIEWPORT: Unified toolbar fused with the titlebar: title and pixel-size subtitle left; Undo, Copy and Save right (HIG toolbar research: Undo belongs in the toolbar). Save is the prominent accent action on macOS 15; on macOS 26+ the system draws the bridged item as a standard toolbar item (probe: NSToolbarItem.style stays .plain under every SwiftUI style, placement and AppKit override tried). The print centred and fit. Leading edge: vertical glass pen-tray rail — 8 tools (the selected drawing tool carries the current ink as a short pencil-lead stroke under its glyph), divider, ink well of 8 colours, S/M/L nibs. Delete and Clear All live in the canvas context menu and ⌫ (HIG: rare, destructive actions stay out of the toolbar). Bottom centre: floating glass capsule (model menu, prompt field, Annotate) that becomes the Claude Code rainbow glimmer strip — a dark terminal strip in both appearances for legibility — while working.

FORM: Light Table — position 3 of the grounded list; seed key 8164278c. Raises: ply discipline (one glass layer); state restyles in place (no reflow on selection, ink or AI progress).

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Revision (user request: simplify)

The pen-tray rail is gone. Tools are a segmented control centred in the toolbar; colour and size live behind one Ink button (current colour) that opens a popover with 8 inks and S/M/L. The screenshot gets the full window width. While a request runs the send button becomes a round stop button in the same spot (Esc also stops); there is no separate Cancel.
