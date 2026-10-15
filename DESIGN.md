---
name: Vocume
description: A screenshot laid on a lit table, marked up by hand or by AI, then copied or saved.
colors:
  table-light: "#CFCFD1"
  terminal-strip: "#1A1A1A"
  ink-red: "#FF3B30"
  ink-orange: "#FF9500"
  ink-yellow: "#FFCC00"
  ink-green: "#34C759"
  ink-blue: "#007AFF"
  ink-purple: "#B052DE"
  ink-black: "#1F1F1F"
  ink-white: "#FFFFFF"
  rainbow-red: "#EB5F57"
  rainbow-orange: "#F58B57"
  rainbow-yellow: "#FAC35F"
  rainbow-green: "#91C882"
  rainbow-blue: "#82AADC"
  rainbow-indigo: "#9B82C8"
  rainbow-violet: "#C882B4"
  shimmer-red: "#FA9B93"
  shimmer-orange: "#FFB989"
  shimmer-yellow: "#FFE19B"
  shimmer-green: "#B9E6B4"
  shimmer-blue: "#B4CDF0"
  shimmer-indigo: "#C3B4E6"
  shimmer-violet: "#E6B4D2"
typography:
  tool-glyph:
    fontFamily: "SF Symbols (system)"
    fontSize: "15pt"
    fontWeight: 500
  prompt:
    fontFamily: "SF Pro (system font)"
    fontSize: "14pt"
    fontWeight: 400
  label:
    fontFamily: "SF Pro (system font)"
    fontSize: "13pt (.callout)"
    fontWeight: 500
  progress:
    fontFamily: "SF Mono (system monospaced)"
    fontSize: "13pt"
    fontWeight: 600
  mark-label:
    fontFamily: "SF Pro (system font)"
    fontSize: "scales with the image (Mark.fontSize)"
    fontWeight: 600
  step-number:
    fontFamily: "SF Pro Rounded (system rounded)"
    fontSize: "15pt × mark unit"
    fontWeight: 700
rounded:
  print: "3pt"
  tool-tile: "10pt"
  note: "14pt"
  rail: "18pt"
  capsule: "9999pt"
spacing:
  rail-stack: "2pt"
  swatch-gap: "4pt"
  rail-padding: "6pt"
  row-gap: "10pt"
  edge: "14pt"
  composer-bottom: "18pt"
  composer-side: "24pt"
  print-inset: "28pt"
components:
  tool-rail:
    rounded: "{rounded.rail}"
    padding: "6pt"
  tool-button:
    rounded: "{rounded.tool-tile}"
    size: "34pt"
    typography: "{typography.tool-glyph}"
  ink-lead:
    rounded: "{rounded.capsule}"
    width: "16pt"
    height: "4pt"
  ink-swatch:
    rounded: "{rounded.capsule}"
    size: "16pt"
    padding: "2pt"
  nib:
    width: "34pt"
    height: "24pt"
  composer:
    rounded: "{rounded.capsule}"
    height: "46pt"
    width: "max 720pt"
    typography: "{typography.prompt}"
  composer-busy:
    backgroundColor: "{colors.terminal-strip}"
    rounded: "{rounded.capsule}"
    height: "46pt"
    typography: "{typography.progress}"
  toast:
    rounded: "{rounded.capsule}"
    padding: "8pt 14pt"
    typography: "{typography.label}"
  error-note:
    rounded: "{rounded.note}"
    padding: "10pt 14pt"
  print:
    rounded: "{rounded.print}"
    padding: "28pt"
---

# Design System: Vocume

## Overview

**Creative North Star: "The Light Table"**

The screenshot is a print laid on a lit table. The table is a quiet grey ground, lit from beneath the print so the eye goes to the work. Tools rest at the table's edge in a pen tray and disappear into the task. The one place the app raises its voice is AI progress, which borrows Claude Code's terminal rainbow so a running request is unmistakable.

Everything else is native macOS: SF Symbols, the system font, system accent, system materials, a unified toolbar fused with the titlebar. Density is low; the print takes the window, the controls take its edges. State restyles in place: selection, ink, nib and AI progress never move or reflow anything.

The system refuses the category default of a dense Preview-style toolbar strip, and it refuses glass on glass.

**Key Characteristics:**
- Graphite or pale-grey table, radial under-light, the print centred and fit with a hairline edge and a soft lift shadow.
- Exactly one glass layer above the print: rail, composer capsule, toast, error note.
- System accent marks selection; the eight mark inks show only as inks (swatches, the ink lead, marks).
- Monospaced rainbow only for AI progress, on a dark terminal strip in both appearances.
- Snappy, short motion (0.18–0.22 s) with Reduce Motion fallbacks everywhere.

## Colors

A neutral, system-driven chrome around eight saturated grease-pencil inks, plus a pastel terminal rainbow reserved for AI.

### Primary
- **System Accent** (`Color.accentColor`, follows the user's setting): selected tool tile fill, selected swatch ring, selected nib dot, the Annotate button, Save on macOS 15, the dashed selection outline on a mark. Never hard-coded.

### Secondary
- **Mark Inks** (`ink-red` … `ink-white`, from `Palette`): the eight named colours a mark can take. They appear in the ink well, as the ink lead under the selected drawing tool, and on the canvas. Red is the default. Text on `ink-yellow` and `ink-white` is black; on every other ink it is white (`Palette.ink(on:)`).

### Tertiary
- **Terminal Rainbow** (`rainbow-*` base, `shimmer-*` glimmer): Claude Code's `rainbow_*` / `*_shimmer` theme keys. Used only inside the busy composer: per-character progress text, the sparkle glyph and the rainbow rule.

### Neutral
- **Graphite Table** (`NSColor.underPageBackgroundColor`, Dark Mode) with a white 0.07 radial glow (start radius 40, end 620, centred).
- **Pale Table** (`table-light`, Light Mode) with a white 0.25 radial glow, same geometry. Lighter than the system mid-grey so the window doesn't read as a dim slab under a light titlebar.
- **Terminal Strip** (`terminal-strip` at 92% opacity): the busy composer's ground in both appearances.
- **Hairlines**: `Color.primary` at 0.1 (light) / 0.18 (dark) on the print; 0.1 on fallback glass; 0.2 on swatches, 0.45 on black and white swatches, 0.6 under Increase Contrast.

### Named Rules
**The Accent Is Selection Rule.** System accent means "this is chosen" or "this is the primary action". It never decorates.

**The Rainbow Belongs To AI Rule.** The terminal rainbow appears only while a request runs, only inside the composer.

## Typography

**Body Font:** SF Pro (system font)
**Label/Mono Font:** SF Mono (system monospaced), AI progress only
**Glyphs:** SF Symbols

**Character:** Plain system type; the canvas content is the subject, so the chrome never competes with it.

### Hierarchy
- **Window title** (system): file name, with the pixel size (`W × H px`) as the toolbar subtitle.
- **Tool glyph** (medium, 15pt): rail tool icons.
- **Prompt** (regular, 14pt): composer text field; Annotate glyph semibold 14pt.
- **Label** (medium, 13pt `.callout`): toast; the error note uses regular callout, up to 3 lines, selectable.
- **Progress** (semibold, 13pt, monospaced, monospaced digits for the elapsed timer `0.0s`).
- **Mark label** (semibold, scaled to the image) and **step number** (bold rounded, 15pt × mark unit): drawn into the image.

## Layout

- Window: 1180 × 820 pt default, minimum 860 × 640; full-size content view, unified toolbar.
- The print is centred and aspect-fit with a 28pt inset on all sides inside the safe area.
- The rail is a leading safe-area inset, 14pt from the window edge, vertically centred, sized to its content.
- The composer floats at the bottom (`safeAreaBar` on macOS 26, `safeAreaInset` on macOS 15): max 720pt wide, 24pt side margins, 18pt from the bottom. The error note stacks 8pt above it.
- The toast sits top-centre, 14pt below the toolbar.
- Toolbar: title and subtitle leading; Undo, fixed spacer (macOS 26), Copy, Save trailing. Delete and Clear All live only in the canvas context menu and on ⌫ / ⌦.

## Elevation & Depth

Three plies, never more: table, print, one glass layer. Depth comes from the print's lift shadow and the glass material; marks carry their own small shadow so they read as ink on the print.

### Shadow Vocabulary
- **Print lift** (black 0.22 light / 0.55 dark, radius 22, y 10): the screenshot on the table.
- **Fallback glass** (black 0.12, radius 12, y 4): only on macOS 15 regular-material glass.
- **Selected tile** (accent 0.35, radius 5, y 2): under the selected tool tile.
- **Mark ink** (black 0.35, radius 3 × unit, y 1 × unit): arrows, boxes, pen strokes, step discs and label pills.

### Named Rules
**The One Ply Rule.** Exactly one glass layer floats over the print, through `floatingGlass(in:)`: Liquid Glass `.regular` on macOS 26, `.regularMaterial` + 0.5pt hairline + fallback shadow on macOS 15. Never glass on glass: controls inside glass use solid fills (the Annotate button is `.borderedProminent`, not glass).

## Shapes

Continuous-corner rounded rectangles and capsules. The print is nearly square-cornered (3pt) so it reads as paper; containers get softer the more they float: tool tile 10pt, error note 14pt, rail 18pt, composer and toast full capsules. Swatches and nibs are circles.

## Components

### Tool Rail (pen tray)
Tools, ink well and nibs in one vertical glass rail.
- **Anatomy:** 8 tool buttons (34 × 34pt, 2pt apart), a 24pt divider, the ink well (2 columns × 4 rows of 16pt swatches, 4pt gaps, 2pt ring padding), a divider, S/M/L nibs (34 × 24pt hit area; dots 5 / 8 / 11pt, stroke widths 0.6 / 1.0 / 1.6). 6pt padding, 18pt corners.
- **Tool selected:** accent-filled 10pt tile, white glyph, soft accent shadow. Unselected: clear tile, primary glyph.
- **Ink lead:** on the selected drawing tool (not Select), a 16 × 4pt capsule of the current ink with a 1pt white 0.9 edge, 3pt above the tile's bottom. It replaces any corner-dot indicator.
- **Swatch selected:** 2pt accent ring. **Nib selected:** accent dot; unselected dots primary at 0.55.
- **Motion:** `.snappy(0.18)` on tool and ink changes; none under Reduce Motion. Nothing moves or reflows.

### Composer (AI capsule)
- **Idle:** 46pt glass capsule: model menu (borderless, `sparkle` + backend name), 20pt divider, plain prompt field, accent capsule Annotate button (22pt `arrow.up` glyph, ⌘↩). Leading 8pt / trailing 6pt padding, 10pt gaps.
- **Busy:** the same capsule becomes a dark terminal strip (terminal-strip at 92%, forced dark scheme) in both appearances. Content: rainbow sparkle (cycles every 150 ms), the stage text with each character in the next base rainbow colour and a 3-character shimmer glimmer sweeping at 1 char / 50 ms from 10 before to 10 after, stepped on a 64 ms tick; elapsed seconds in secondary; bordered capsule Cancel (Esc). The border is the rainbow rule: ~9pt segments, 2pt stroke, colour index shifting every 150 ms. New requests are blocked; the canvas stays editable.
- **Reduce Motion:** timelines pause, the glimmer parks off-screen, the rule and sparkle hold still.
- **Motion:** `.snappy(0.22)` crossfade between idle and busy, and for the error note.

### Toast
Glass capsule, `checkmark.circle.fill` + callout medium text, 14 × 8pt padding, top-centre. Slides from the top with opacity; opacity only under Reduce Motion.

### Error Note
Glass 14pt rounded rectangle above the composer, orange `exclamationmark.triangle.fill`, selectable callout text (3 lines max), icon-only borderless Dismiss. Hidden while busy.

### Toolbar Buttons
Undo (`arrow.uturn.backward`, disabled when empty), Copy (`doc.on.doc`, ⇧⌘C), Save (title only, ⌘S). Save is `.borderedProminent`: accent-filled on macOS 15; on macOS 26 the system draws it as a standard toolbar item and no SwiftUI or AppKit style changes that. Treat this as a platform limitation, not a design choice.

### Print and Marks
The screenshot with a 3pt clip, 0.5pt hairline and print lift shadow; the canvas context menu holds Delete Mark, Clear All Marks, Copy Image, Save…. Mark selection is a 1.5pt accent dashed outline (5/4). Text marks edit inline in a field styled like their pill (semibold, ink-on-colour, pill-height × 0.3 corners). Highlight multiplies ink at 0.45; redaction is a solid fill.

### Keyboard and Accessibility
- Tools: V Select, A Arrow, R Box, H Highlight, X Redact, P Pen, T Text, N Numbered Step (ignored while typing). ⌘Z undo, ⌫/⌦ delete, Esc cancels a running request first, then deselects. ⌘↩ annotates, ⇧⌘C copies, ⌘S saves.
- Every control has a help tooltip with its shortcut, a VoiceOver label and `.isSelected` when chosen; swatches are named by colour. The canvas announces its mark count. Decorative pieces (ink lead, rainbow rule) are hidden from VoiceOver; progress reads as its stage text.
- Respect Reduce Motion (above), Increase Contrast (firmer swatch hairlines) and Dark Mode (separate table, hairline and shadow values).

## Do's and Don'ts

### Do:
- **Do** route every floating surface through `floatingGlass(in:)` and every bottom bar through `floatingBottomBar`.
- **Do** gate Liquid Glass and other macOS 26 API behind `#available(macOS 26, *)` with a macOS 15 fallback.
- **Do** use system accent for selection and the primary action, and `Palette` inks only for marks and their previews.
- **Do** give every animation a Reduce Motion path (nil animation, opacity transition, or paused timeline).
- **Do** use `ObservableObject` / `@Published` and plain property wrappers; the app builds with the Command Line Tools only, so no SwiftUI macros (`@Observable`, `#Preview`).

### Don't:
- **Don't** put glass inside glass; controls inside a glass surface use solid or bordered fills.
- **Don't** use the terminal rainbow or monospaced type outside AI progress.
- **Don't** let selection, ink, nib or busy state change layout.
- **Don't** put rare or destructive actions (Delete, Clear All) in the toolbar or rail.
- **Don't** add a Preview-style horizontal tool strip; tools live in the leading rail.


## Revision: simplified layout

Supersedes the rail sections above: tools are a segmented control centred in the window toolbar; colour and size live behind one Ink toolbar button that opens a popover (8 inks in a 4×2 grid of 22pt swatches, S/M/L size buttons). No rail. During a request the composer's round accent send button becomes a round stop button in place; there is no Cancel button.


## Revision: AI bar and Settings

The AI bar is one 44pt glass capsule with three slots, every round control inset 6pt so it sits concentric: a borderless sparkle menu (provider choice + "AI Settings…"), the plain prompt field (14pt, placeholder names the provider), and a 32pt solid-accent round action (send ↑, becomes stop ■ while busy). Max width 640pt, 16pt from the bottom. Errors sit above it as a one-line glass note (14pt corners) with a dismiss ×. With no usable provider the bar says so and offers Settings…; with AI off it is hidden.

Settings is a standard grouped Form (520pt wide): an "Annotate with AI" switch, then one row per provider (status dot: green ready / grey unavailable / spinner checking; name; caption with the detected account or the reason plus fix), a switch that reads off while unavailable, and an Ollama model picker. Footer: "Detected automatically on this Mac." + Check Again.

## Revision: resize handles and custom inks

- **Handles:** a selected box, highlight or redaction shows 8 round handles (9pt, white fill, 1.5pt accent ring, faint lift shadow) on its frame, with the dashed accent outline running through them; an arrow shows a handle on each end and no outline. Pen, text and steps keep the dashed bounds outline and are sized with S/M/L. Hovering a handle shows the matching resize cursor (an open hand on arrow ends). A press on a handle without a drag counts as a click, so a selected arrow's label (which sits on its tail handle) still opens for editing.
- **Ink popover:** below the 8 inks, a divider and a custom row of four 22pt circles: the 2 most recent custom colours (dashed placeholder rings until there are any), the screen eyedropper (`eyedropper`, `NSColorSampler`) and the system colour panel (`paintpalette`). Tool circles are neutral (primary 0.08 fill, secondary glyph); the rainbow stays reserved for AI. Custom inks are `#RRGGBB`, their label text black or white by WCAG luminance. Colour changes to one mark in a row (trying swatches, dragging in the panel) are one undo step.

