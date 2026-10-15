# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos (native SwiftUI/AppKit menu-bar app; not one of the schema's web/ios/android/adaptive values — follow the macOS Human Interface Guidelines)

## Users

Any Mac user who takes screenshots and needs to mark them up quickly: pointing at something, hiding something, explaining something. AI tooling users are a large share, but the editor must make sense to someone who has never opened a terminal.

## Product Purpose

Vocume captures an area, window or screen (its own global shortcuts or its menu-bar menu, using macOS's native selection) and opens it in an annotation editor. Users mark it up by hand — arrows, boxes, highlights, redaction, pen, text, numbered steps — or describe what they want and let Claude or Codex mark it up. Success: a clear, correctly annotated image on the clipboard or disk within seconds, with no fiddling.

## Positioning

AI annotation that lands on exact words and letters: the model decides *what* to mark, on-device OCR plus pixel analysis decides *where*. It runs on the user's existing Claude Code / Codex subscription login or a local Ollama vision model, with no API keys; Settings shows what was detected and lets the user choose providers or turn AI off.

## Operating Context

- Annotated images go next into AI agents (Claude Code, Codex, ChatGPT), issues and PRs (GitHub, Linear, Jira), and chat and docs (Slack, Notion).
- The editor opens right after the user captures, in the middle of other work; it must come to the front, be instantly legible, and be easy to dismiss.
- Lives in the menu bar; while an editor or Settings is open it is a regular app (Dock, ⌘-Tab, menu bar). One editor window per capture.

## Capabilities and Constraints

- Tools: select, arrow, line, box, ellipse, highlight, redact (solid, secure), pen, text, numbered step, crop (by hand or by AI, non-destructive); shapes resize by their handles, Shift constrains (square, circle, 45°, proportions); arrow keys nudge; undo and redo; zoom (toolbar menu, ⌘+/⌘−/⌘0/⌘9, pinch); drag the annotated image out to other apps; 8 named colours plus custom colours (screen eyedropper, system colour panel); S/M/L sizes; undo; copy (⇧⌘C) and save (⌘S) at full resolution.
- AI: Claude or Codex via the installed CLI; AI marks are ordinary editable marks. Requests are blocked while one runs.
- Must build with only the Xcode Command Line Tools (no SwiftUI macros: `@State`, `@Observable`, `#Preview`). macOS 15+.
- Quality over speed is a standing rule for AI behaviour.

## Product Principles

1. Hand tools and AI are equals: neither is buried behind the other.
2. Out of the way until needed: the editor appears, does its job, and leaves.
3. Precision is the promise: marks land exactly where they should, by hand or by AI.
4. Native, not novel: behave like a well-made Mac app so nothing needs learning.

## Accessibility & Inclusion

Respect Reduce Motion, Increase Contrast and Dark Mode; every tool reachable by keyboard and labelled for VoiceOver.
