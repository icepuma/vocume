import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Owns the menu-bar item and the editor windows.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var sources: ScreenshotSources?
    private var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_: Notification) {
        installEditMenu()
        let sources = ScreenshotSources { [weak self] url in self?.openEditor(for: url) }
        self.sources = sources

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Vocume")
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Watching \(sources.folder.lastPathComponent) + clipboard", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Open Image…", action: #selector(openImage), keyEquivalent: "o").target = self
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    /// An Edit menu, so ⌘C / ⌘V / ⌘A work in text fields even though the app has no menu bar.
    private func installEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let main = NSMenu()
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
        NSApp.mainMenu = main
    }

    func openEditor(for url: URL) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        let model = EditorModel(url: url)
        model.window = window
        window.title = url.lastPathComponent
        window.contentView = NSHostingView(rootView: EditorView(model: model))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        windows.append(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        windows.removeAll { $0 === notification.object as? NSWindow }
    }

    @objc private func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { openEditor(for: url) }
    }
}
