import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The menu-bar item, the main menu, global capture shortcuts, and the capture → editor flow.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var captureItems: [CaptureMode: NSMenuItem] = [:]
    private var capturing = false

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.mainMenu = mainMenu()
        installStatusItem()
        AISettings.shared.refresh()  // detect AI logins once at launch; Settings re-checks on open
        let shortcuts = CaptureShortcuts.shared
        shortcuts.onTrigger = { [weak self] mode in self?.capture(mode) }
        shortcuts.register()
    }

    /// Clicking the Dock icon brings the last editor forward; opening the app from Finder or
    /// Spotlight with nothing open shows Settings.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        Windows.shared.reopen()
        return true
    }

    // MARK: Capture

    func capture(_ mode: CaptureMode) {
        guard !capturing else { return }
        capturing = true
        Task {
            let url = await Capture.run(mode)
            capturing = false
            if let url { Windows.shared.openEditor(for: url) }
        }
    }

    @objc private func captureFromMenu(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? String, let capture = CaptureMode(rawValue: mode) else { return }
        // Let the menu close first, so it isn't in the screenshot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            MainActor.assumeIsolated { self.capture(capture) }
        }
    }

    @objc private func annotateClipboard() {
        let pasteboard = NSPasteboard.general
        guard
            let png = pasteboard.data(forType: .png)
                ?? pasteboard.data(forType: .tiff).flatMap({
                    NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
                })
        else { return NSSound.beep() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Clipboard \(UUID().uuidString.prefix(6)).png")
        if (try? png.write(to: url)) != nil { Windows.shared.openEditor(for: url) }
    }

    @objc private func openImage() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        if panel.runModal() == .OK, let url = panel.url { Windows.shared.openEditor(for: url) }
    }

    @objc private func openSettings() { Windows.shared.showSettings() }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Annotate screenshots by hand or with AI.")
        ])
    }

    // Editor commands, routed to the editor in front.
    @objc private func saveImage() { Windows.shared.keyEditor?.save() }
    @objc private func copyImage() { Windows.shared.keyEditor?.copyImage() }
    // While a text field has the cursor, undo and redo belong to its text.
    @objc private func undoMark() {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView {
            text.undoManager?.undo()
        } else {
            Windows.shared.keyEditor?.undo()
        }
    }
    @objc private func redoMark() {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView {
            text.undoManager?.redo()
        } else {
            Windows.shared.keyEditor?.redo()
        }
    }
    @objc private func openHelp() {
        NSWorkspace.shared.open(URL(string: "https://github.com/icepuma/vocume#readme")!)
    }
    @objc private func zoomIn() { Windows.shared.keyEditor?.zoomIn() }
    @objc private func zoomOut() { Windows.shared.keyEditor?.zoomOut() }
    @objc private func actualSize() { Windows.shared.keyEditor?.setZoom(1) }
    @objc private func zoomToFit() { Windows.shared.keyEditor?.zoomToFit() }
    @objc private func deleteMark() { Windows.shared.keyEditor?.deleteSelected() }

    // MARK: Menus

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = LogoGlyph.menuBarImage()
        let menu = NSMenu()
        menu.delegate = self
        addCaptureItems(to: menu, keepReferences: true)
        menu.addItem(.separator())
        menu.addItem(menuItem("Open Image…", #selector(openImage), "o"))
        menu.addItem(menuItem("Annotate Clipboard Image", #selector(annotateClipboard), ""))
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings…", #selector(openSettings), ","))
        menu.addItem(menuItem("About Vocume", #selector(showAbout), ""))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Vocume", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    /// The menu bar shown while an editor or Settings is open.
    private func mainMenu() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu(title: "Vocume")
        app.addItem(menuItem("About Vocume", #selector(showAbout), ""))
        app.addItem(.separator())
        app.addItem(menuItem("Settings…", #selector(openSettings), ","))
        app.addItem(.separator())
        let services = NSMenu(title: "Services")
        app.addItem(withTitle: "Services", action: nil, keyEquivalent: "").submenu = services
        NSApp.servicesMenu = services
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Vocume", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(
            withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h"
        ).keyEquivalentModifierMask = [.command, .option]
        app.addItem(
            withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Vocume", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let file = NSMenu(title: "File")
        addCaptureItems(to: file, keepReferences: false)
        file.addItem(.separator())
        file.addItem(menuItem("Open Image…", #selector(openImage), "o"))
        file.addItem(menuItem("Annotate Clipboard Image", #selector(annotateClipboard), ""))
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.addItem(menuItem("Save…", #selector(saveImage), "s"))
        let copy = menuItem("Copy Image", #selector(copyImage), "c")
        copy.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(copy)

        let edit = NSMenu(title: "Edit")
        edit.addItem(menuItem("Undo", #selector(undoMark), "z"))
        edit.addItem(menuItem("Redo", #selector(redoMark), "Z"))
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let delete = menuItem("Delete Mark", #selector(deleteMark), "\u{8}")
        delete.keyEquivalentModifierMask = []
        edit.addItem(delete)
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let view = NSMenu(title: "View")
        view.addItem(menuItem("Zoom In", #selector(zoomIn), "+"))
        view.addItem(menuItem("Zoom Out", #selector(zoomOut), "-"))
        view.addItem(menuItem("Actual Size", #selector(actualSize), "0"))
        view.addItem(menuItem("Zoom to Fit", #selector(zoomToFit), "9"))

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(
            withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window

        let help = NSMenu(title: "Help")
        help.addItem(menuItem("Vocume Help", #selector(openHelp), "?"))
        NSApp.helpMenu = help

        for submenu in [app, file, edit, view, window, help] {
            main.addItem(withTitle: submenu.title, action: nil, keyEquivalent: "").submenu = submenu
        }
        return main
    }

    private func addCaptureItems(to menu: NSMenu, keepReferences: Bool) {
        for mode in CaptureMode.allCases {
            let entry = NSMenuItem(title: mode.title, action: #selector(captureFromMenu(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = mode.rawValue
            entry.image = NSImage(systemSymbolName: mode.symbol, accessibilityDescription: nil)
            menu.addItem(entry)
            if keepReferences { captureItems[mode] = entry }
        }
        updateShortcutHints()
    }

    /// Shows each global shortcut next to its menu item.
    private func updateShortcutHints() {
        for (mode, entry) in captureItems {
            let shortcut = CaptureShortcuts.shared.shortcuts[mode]
            entry.keyEquivalent = shortcut?.key.lowercased() ?? ""
            entry.keyEquivalentModifierMask = shortcut?.flags ?? []
        }
    }

    func menuWillOpen(_: NSMenu) { updateShortcutHints() }

    private func menuItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        return entry
    }
}
