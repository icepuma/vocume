import AppKit
import CoreGraphics

/// The ways Vocume captures, all through macOS's own `screencapture` so selection, window
/// highlighting, Space-to-toggle and Esc-to-cancel behave exactly like the system shortcuts.
enum CaptureMode: String, CaseIterable, Identifiable, Sendable {
    case area, window, screen, timedScreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .area: "Capture Area"
        case .window: "Capture Window"
        case .screen: "Capture Entire Screen"
        case .timedScreen: "Capture Screen in 5 Seconds"
        }
    }

    var symbol: String {
        switch self {
        case .area: "rectangle.dashed"
        case .window: "macwindow"
        case .screen: "display"
        case .timedScreen: "timer"
        }
    }

    /// Modes that get a global keyboard shortcut. Defaults mirror the system ones (⇧⌘3/4) with ⌥
    /// added, so they never clash with macOS.
    static let shortcutModes: [CaptureMode] = [.area, .window, .screen]

    var defaultShortcut: Shortcut? {
        switch self {
        case .area: Shortcut(keyCode: 21, modifiers: Shortcut.defaultModifiers, key: "4")
        case .window: Shortcut(keyCode: 13, modifiers: Shortcut.defaultModifiers, key: "W")
        case .screen: Shortcut(keyCode: 20, modifiers: Shortcut.defaultModifiers, key: "3")
        case .timedScreen: nil
        }
    }

    /// `screencapture` arguments before the output path.
    @MainActor fileprivate var arguments: [String] {
        switch self {
        case .area: ["-i", "-J", "selection"]
        case .window: ["-i", "-J", "window"]
        case .screen: ["-D", "\(Self.displayUnderPointer)"]
        case .timedScreen: ["-T", "5", "-D", "\(Self.displayUnderPointer)"]
        }
    }

    /// `screencapture -D` numbers displays from 1 in the system's order, which `NSScreen.screens`
    /// shares (main display first).
    @MainActor private static var displayUnderPointer: Int {
        let pointer = NSEvent.mouseLocation
        return (NSScreen.screens.firstIndex { NSMouseInRect(pointer, $0.frame, false) } ?? 0) + 1
    }
}

enum Capture {
    /// Captures with `mode` and returns the image file, or `nil` if the user cancelled.
    static func run(_ mode: CaptureMode) async -> URL? {
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: ".")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Vocume \(stamp).png")
        let arguments = await MainActor.run { mode.arguments } + [url.path]
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = arguments
            process.terminationHandler = { _ in done.resume() }
            if (try? process.run()) == nil { done.resume() }
        }
        // Esc leaves no file.
        guard FileManager.default.fileExists(atPath: url.path), NSImage(contentsOf: url) != nil else { return nil }
        return url
    }
}
