import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut: a virtual key code plus modifiers, with the key's label as typed.
struct Shortcut: Codable, Equatable, Sendable {
    var keyCode: UInt32
    /// `NSEvent.ModifierFlags` raw value (device-independent bits only).
    var modifiers: UInt
    var key: String

    static let defaultModifiers = NSEvent.ModifierFlags([.option, .shift, .command]).rawValue

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// "⌥⇧⌘4", in Apple's modifier order.
    var display: String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + key
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    /// A shortcut from a key press, if it has a modifier that makes it safe as a global shortcut.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        let label = Self.label(for: event)
        guard !label.isEmpty else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: flags.rawValue, key: label)
    }

    init(keyCode: UInt32, modifiers: UInt, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    private static func label(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        default:
            return (event.charactersIgnoringModifiers ?? "").uppercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

/// The capture shortcuts the user set (UserDefaults), registered system-wide.
@MainActor final class CaptureShortcuts: ObservableObject {
    static let shared = CaptureShortcuts()

    @Published private(set) var shortcuts: [CaptureMode: Shortcut] = [:]
    /// Shortcuts macOS refused (usually because another app already owns the combination).
    @Published private(set) var failed: Set<CaptureMode> = []
    /// Called when a registered shortcut is pressed anywhere in macOS.
    var onTrigger: ((CaptureMode) -> Void)?

    private let defaults = UserDefaults.standard
    private var registered: [EventHotKeyRef] = []
    private var handlerInstalled = false

    private init() {
        for mode in CaptureMode.shortcutModes {
            let key = "shortcut.\(mode.rawValue)"
            if let data = defaults.data(forKey: key) {
                // An empty payload means the user cleared it.
                shortcuts[mode] = try? JSONDecoder().decode(Shortcut.self, from: data)
            } else {
                shortcuts[mode] = mode.defaultShortcut
            }
        }
    }

    func set(_ shortcut: Shortcut?, for mode: CaptureMode) {
        shortcuts[mode] = shortcut
        let data = shortcut.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        defaults.set(data, forKey: "shortcut.\(mode.rawValue)")
        register()
    }

    /// (Re)registers every shortcut. Called at launch and after any change.
    func register() {
        unregister()
        installHandler()
        failed = []
        for (index, mode) in CaptureMode.shortcutModes.enumerated() {
            guard let shortcut = shortcuts[mode] else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index))
            let status = RegisterEventHotKey(
                shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { registered.append(ref) } else { failed.insert(mode) }
        }
    }

    /// Suspends all shortcuts, so the recorder can capture a combination that is currently in use.
    func unregister() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered.removeAll()
    }

    fileprivate func fire(_ index: UInt32) {
        guard Int(index) < CaptureMode.shortcutModes.count else { return }
        onTrigger?(CaptureMode.shortcutModes[Int(index)])
    }

    private static let signature: OSType = 0x564F_434D  // 'VOCM'

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var id = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &id)
                // Carbon delivers hot keys on the main thread.
                MainActor.assumeIsolated { CaptureShortcuts.shared.fire(id.id) }
                return noErr
            }, 1, &spec, nil, nil)
    }
}
