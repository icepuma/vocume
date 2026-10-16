import AppKit
import SwiftUI

/// Settings › Shortcuts: a global shortcut per capture mode.
struct ShortcutsPane: View {
    @ObservedObject var shortcuts = CaptureShortcuts.shared

    var body: some View {
        Form {
            captureSection
            Section {
                LabeledContent {
                    Button("Keyboard Shortcuts…") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                    }
                } label: {
                    Text("Use ⇧⌘3 and ⇧⌘4")
                    Text("macOS keeps them for itself. Turn them off there, then record them here.")
                }
            }
        }
        .settingsPane()
    }

    private var captureSection: some View {
        Section {
            ForEach(CaptureMode.shortcutModes) { mode in
                LabeledContent {
                    ShortcutRecorder(mode: mode)
                } label: {
                    Label(mode.title, systemImage: mode.symbol)
                    // Explanations go under the row's title, as in System Settings; footers hold buttons.
                    if shortcuts.failed.contains(mode) {
                        Text("Another app is using this shortcut.").foregroundStyle(.orange)
                    } else if mode == .area {
                        Text("Drag to select, or press Space for a window.")
                    }
                }
            }
        } header: {
            Text("Capture")
        }
    }
}

/// Click to record a shortcut; Esc cancels, ⌫ clears. Global shortcuts are paused while recording,
/// so the current combination can be pressed again.
private struct ShortcutRecorder: View {
    let mode: CaptureMode
    @ObservedObject private var shortcuts = CaptureShortcuts.shared
    @StateObject private var recorder = Recorder()

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recorder.isRecording ? recorder.stop() : recorder.start(for: mode)
            } label: {
                Text(recorder.isRecording ? "Type shortcut…" : shortcuts.shortcuts[mode]?.display ?? "Record Shortcut")
                    .monospacedDigit()
                    .frame(minWidth: 110)
            }
            .buttonStyle(.bordered)
            .tint(recorder.isRecording ? .accentColor : nil)
            .help("Click, then press the new shortcut. ⌫ removes it, Esc cancels.")
            if shortcuts.shortcuts[mode] != nil, !recorder.isRecording {
                Button("Clear", systemImage: "xmark.circle.fill") { shortcuts.set(nil, for: mode) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove shortcut")
            }
        }
    }
}

@MainActor private final class Recorder: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?

    func start(for mode: CaptureMode) {
        CaptureShortcuts.shared.unregister()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                switch Int(event.keyCode) {
                case 53: self?.stop()  // Esc
                case 51, 117:  // ⌫ / ⌦
                    CaptureShortcuts.shared.set(nil, for: mode)
                    self?.stop()
                default:
                    guard let shortcut = Shortcut(event: event) else {
                        NSSound.beep()  // needs ⌘, ⌥ or ⌃
                        return
                    }
                    CaptureShortcuts.shared.set(shortcut, for: mode)
                    self?.stop()
                }
            }
            return nil
        }
    }

    func stop() {
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
        isRecording = false
        CaptureShortcuts.shared.register()
    }

    isolated deinit {
        monitor.map(NSEvent.removeMonitor)
    }
}
