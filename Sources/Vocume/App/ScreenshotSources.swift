import AppKit

/// Notices new screenshots: PNGs appearing in the system screenshot folder, and images put on the
/// clipboard (screenshots set to "Clipboard" never touch disk).
@MainActor final class ScreenshotSources {
    /// Marks Vocume's own clipboard writes, so copying an annotated image doesn't reopen it.
    static let ownPasteboardType = NSPasteboard.PasteboardType("dev.icepuma.vocume")
    /// File names Vocume saved itself, so the folder watcher skips them.
    static var ownFileNames = Set<String>()

    let folder: URL
    private let onScreenshot: (URL) -> Void
    private var seen = Set<String>()
    private var folderSource: DispatchSourceFileSystemObject?
    private var clipboardTimer: Timer?
    private var pasteboardChangeCount = NSPasteboard.general.changeCount

    init(onScreenshot: @escaping (URL) -> Void) {
        self.onScreenshot = onScreenshot
        folder = Self.screenshotFolder()
        seen = Set(pngNames())
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: open(folder.path, O_EVTONLY),
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.scanFolder() }
        source.resume()
        folderSource = source
        // Scheduled on the main run loop, so it fires on the main actor.
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkClipboard() }
        }
    }

    isolated deinit {
        folderSource?.cancel()
        clipboardTimer?.invalidate()
    }

    /// Where macOS saves screenshots (`defaults read com.apple.screencapture location`), else the Desktop.
    static func screenshotFolder() -> URL {
        let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        return URL(fileURLWithPath: ((location ?? "~/Desktop") as NSString).expandingTildeInPath)
    }

    // ponytail: any new PNG in the folder opens; filter by name if that gets noisy (the name is localized).
    private func pngNames() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".png") && !$0.hasPrefix(".") }
    }

    private func scanFolder() {
        for name in pngNames() where !seen.contains(name) {
            seen.insert(name)
            if !Self.ownFileNames.contains(name) { onScreenshot(folder.appendingPathComponent(name)) }
        }
    }

    // ponytail: any newly copied image opens (screenshots carry no marker); add a menu toggle if that gets annoying.
    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != pasteboardChangeCount else { return }
        pasteboardChangeCount = pasteboard.changeCount
        guard pasteboard.types?.contains(Self.ownPasteboardType) != true,
            let png = pasteboard.data(forType: .png)
                ?? pasteboard.data(forType: .tiff).flatMap({
                    NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
                })
        else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clipboard-\(Int(Date().timeIntervalSince1970)).png")
        if (try? png.write(to: url)) != nil { onScreenshot(url) }
    }
}
