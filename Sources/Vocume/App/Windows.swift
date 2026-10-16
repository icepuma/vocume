import AppKit
import SwiftUI

/// Owns every Vocume window and the app's presence in the Dock.
///
/// Vocume lives in the menu bar, but while an editor or Settings is open it behaves like a normal
/// app: Dock icon, ⌘-Tab, a menu bar. When the last window closes it goes back to the menu bar,
/// and macOS hands focus back to the previous app.
@MainActor final class Windows: NSObject, NSWindowDelegate {
    static let shared = Windows()

    private var editors: [ObjectIdentifier: (window: NSWindow, model: EditorModel)] = [:]
    private var settingsWindow: NSWindow?
    private var cascadePoint = NSPoint.zero
    /// Most recently opened editor last, for Dock-icon clicks.
    private var editorOrder: [ObjectIdentifier] = []
    /// The app the user was in before Vocume came forward; focus goes back to it afterwards.
    private var previousApp: NSRunningApplication?

    /// The editor in front, for menu commands.
    var keyEditor: EditorModel? {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return nil }
        return editors[ObjectIdentifier(window)]?.model
    }

    // Edit ▸ Undo / Redo (⌘Z, ⇧⌘Z). Typing in a field undoes the typing first; once the text has
    // nothing left to undo (or the prompt merely has the cursor), they undo and redo marks. Text and
    // marks keep separate histories, so redo goes to whichever was undone last.
    private var lastUndoneText = false

    func undo() {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.undoManager?.canUndo == true {
            text.undoManager?.undo()
            lastUndoneText = true
        } else {
            keyEditor?.undo()
            lastUndoneText = false
        }
    }

    func redo() {
        let text = NSApp.keyWindow?.firstResponder as? NSTextView
        let canRedoMarks = keyEditor?.redoStack.isEmpty == false
        if let text, text.undoManager?.canRedo == true, lastUndoneText || !canRedoMarks {
            text.undoManager?.redo()
        } else {
            keyEditor?.redo()
        }
    }

    // MARK: Editors

    func openEditor(for url: URL) {
        let model = EditorModel(url: url)
        let screen = Self.screenUnderPointer
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.editorSize(for: model.image, on: screen)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        model.window = window
        window.title = url.lastPathComponent
        window.toolbarStyle = .unified  // the view's SwiftUI toolbar fills it (scene bridging)
        window.contentView = NSHostingView(rootView: EditorView(model: model))
        window.isReleasedWhenClosed = false
        window.delegate = self
        if editors.isEmpty {
            // Centre on the screen the user is working on (where the pointer is).
            let area = screen.visibleFrame
            window.setFrameOrigin(
                NSPoint(x: area.midX - window.frame.width / 2, y: area.midY - window.frame.height / 2))
            cascadePoint = window.cascadeTopLeft(from: .zero)
        } else {
            cascadePoint = window.cascadeTopLeft(from: cascadePoint)
        }
        editors[ObjectIdentifier(window)] = (window, model)
        editorOrder.append(ObjectIdentifier(window))
        present(window)
    }

    /// Brings the most recent editor forward (Dock icon click), else Settings.
    func reopen() {
        if let id = editorOrder.last, let window = editors[id]?.window {
            present(window)
        } else {
            showSettings()
        }
    }

    private static var screenUnderPointer: NSScreen {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    /// Fits the screenshot (at its point size) plus the editor's chrome, within 85% of the screen.
    private static func editorSize(for image: NSImage, on screen: NSScreen) -> NSSize {
        let screen = screen.visibleFrame.size
        let chrome = NSSize(width: 56, height: 52 + 56 + 76)  // toolbar, print margins, AI bar
        let wanted = NSSize(width: image.size.width + chrome.width, height: image.size.height + chrome.height)
        return NSSize(
            width: min(max(wanted.width, EditorView.minimumSize.width), screen.width * 0.85),
            height: min(max(wanted.height, EditorView.minimumSize.height), screen.height * 0.85)
        )
    }

    // MARK: Settings

    func showSettings() {
        AISettings.shared.refresh()
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: SettingsPanes.controller())
            window.styleMask = [.titled, .closable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.center()
            settingsWindow = window
        }
        if let settingsWindow { present(settingsWindow) }
    }

    // MARK: Presence

    /// Shows a window in front and focused. Every caller is answering something the user just did
    /// (a shortcut, a menu item, a Dock click), which is what macOS's cooperative activation allows.
    /// Order matters: activation policy first, then the window, then the activation request.
    private func present(_ window: NSWindow) {
        if !NSApp.isActive, let front = NSWorkspace.shared.frontmostApplication, front != .current {
            previousApp = front
        }
        updatePresence(opening: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate()
        // macOS may decline an activation request (seen after global shortcuts); ask once more.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MainActor.assumeIsolated {
                guard !NSApp.isActive, window.isVisible else { return }
                window.orderFrontRegardless()
                NSApp.activate()
            }
        }
    }

    /// Regular app (Dock, ⌘-Tab, menu bar) while any window is open; menu-bar only otherwise.
    /// Going back to the menu bar hands focus to the app the user came from.
    private func updatePresence(opening: Bool = false) {
        let hasWindows = opening || !editors.isEmpty || settingsWindow?.isVisible == true
        let policy: NSApplication.ActivationPolicy = hasWindows ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if policy == .accessory {
            if let previous = previousApp, !previous.isTerminated {
                NSApp.yieldActivation(to: previous)
                previous.activate()
            } else {
                NSApp.hide(nil)
            }
            previousApp = nil
        }
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ window: NSWindow) -> Bool {
        guard let model = editors[ObjectIdentifier(window)]?.model, model.hasUnexportedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "Close without copying or saving?"
        alert.informativeText = "Your annotations on “\(window.title)” will be lost."
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Close").hasDestructiveAction = true
        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn: model.save(thenClose: true)
            case .alertThirdButtonReturn:
                model.hasUnexportedChanges = false
                window.close()
            default: break
            }
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        editors[ObjectIdentifier(window)] = nil
        editorOrder.removeAll { $0 == ObjectIdentifier(window) }
        // After this close finishes, so `isVisible` is already false for the closing window.
        DispatchQueue.main.async { MainActor.assumeIsolated { self.updatePresence() } }
    }
}
