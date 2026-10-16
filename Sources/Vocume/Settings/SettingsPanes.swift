import AppKit
import ServiceManagement
import SwiftUI
import VocumeCore

/// The Settings window's panes as toolbar tabs, like any Mac app's: General, Shortcuts, AI. The
/// window title follows the pane, the window fits each pane, and it reopens on the last one used.
@MainActor enum SettingsPanes {
    static func controller() -> NSTabViewController {
        let tabs = RememberingTabs()
        tabs.tabStyle = .toolbar
        let panes: [(String, String, AnyView)] = [
            ("General", "gearshape", AnyView(GeneralPane())),
            ("Shortcuts", "keyboard", AnyView(ShortcutsPane())),
            ("AI", "sparkles", AnyView(AIPane(settings: .shared))),
        ]
        for (title, symbol, view) in panes {
            let hosting = NSHostingController(rootView: view)
            hosting.sizingOptions = .preferredContentSize
            hosting.title = title
            let item = NSTabViewItem(viewController: hosting)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        tabs.selectedTabViewItemIndex = min(UserDefaults.standard.integer(forKey: RememberingTabs.key), panes.count - 1)
        return tabs
    }
}

private final class RememberingTabs: NSTabViewController {
    static let key = "settingsPane"

    override func viewWillAppear() {
        super.viewWillAppear()
        view.window?.title = tabViewItems[selectedTabViewItemIndex].label
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        UserDefaults.standard.set(selectedTabViewItemIndex, forKey: Self.key)
        view.window?.title = tabViewItem?.label ?? "Settings"
    }
}

/// Settings › General: how Vocume starts.
struct GeneralPane: View {
    @StateObject private var login = LoginItem()

    var body: some View {
        Form {
            Section {
                // A closure, not `set: login.set`: Swift 6.3 crashes converting the method itself.
                Toggle(isOn: Binding(get: { login.isOn }, set: { login.set($0) })) {
                    Text("Open at Login")
                    Text("Vocume waits in the menu bar, ready for your capture shortcuts.")
                }
                if login.needsApproval {
                    LabeledContent {
                        Button("Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    } label: {
                        Text("Needs your approval")
                        Text("Allow Vocume under Login Items in System Settings.")
                    }
                }
            }
        }
        .settingsPane()
        .onAppear(perform: login.refresh)  // it can be changed in System Settings meanwhile
    }
}

/// Settings › AI: whether to use AI at all, and which detected providers to offer.
struct AIPane: View {
    @ObservedObject var settings: AISettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.isEnabled) {
                    Text("Annotate with AI")
                    Text(
                        "Describe the markup and an AI places the marks. Claude and Codex receive the screenshot; Ollama keeps it on this Mac."
                    )
                }
            }

            Section {
                ForEach(AIBackend.allCases) { backend in
                    ProviderRow(settings: settings, backend: backend)
                }
            } header: {
                Text("Providers")
            } footer: {
                // macOS form footers hold trailing buttons.
                HStack {
                    Spacer()
                    if !settings.checking.isEmpty {
                        ProgressView().controlSize(.small)
                    }
                    Button("Check Again", action: settings.refresh)
                        .disabled(!settings.checking.isEmpty)
                }
            }
            .disabled(!settings.isEnabled)
        }
        .settingsPane()
    }
}

extension View {
    /// The shared shape of every Settings pane: a grouped form, 480pt wide, as tall as its content.
    func settingsPane() -> some View {
        formStyle(.grouped)
            .frame(width: 480)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One provider: what it is, what detection found, and the switch to offer it.
private struct ProviderRow: View {
    @ObservedObject var settings: AISettings
    let backend: AIBackend

    private var status: ProviderStatus {
        settings.checking.contains(backend) ? .checking : settings.status[backend] ?? .checking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Shows off while unavailable (the stored choice is kept for when it becomes available).
            Toggle(
                isOn: Binding(
                    get: { status.isReady && settings.isAllowed(backend) },
                    set: { settings.setAllowed(backend, $0) }
                )
            ) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    indicator
                    VStack(alignment: .leading, spacing: 2) {
                        Text(backend.displayName)
                        statusText
                    }
                }
            }
            .disabled(!status.isReady)

            if backend == .ollama, status.isReady {
                Picker("Model", selection: $settings.ollamaModel) {
                    ForEach(settings.ollamaModels, id: \.self) { Text($0).tag($0) }
                }
                .disabled(!settings.isAllowed(.ollama))
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var indicator: some View {
        switch status {
        case .checking:
            ProgressView().controlSize(.small).frame(width: 10, height: 10)
        case .ready:
            Circle().fill(.green).frame(width: 8, height: 8).accessibilityLabel("Available")
        case .unavailable:
            Circle().fill(.secondary.opacity(0.5)).frame(width: 8, height: 8).accessibilityLabel("Unavailable")
        }
    }

    @ViewBuilder private var statusText: some View {
        switch status {
        case .checking:
            Text("Checking…").font(.caption).foregroundStyle(.secondary)
        case .ready(let detail):
            Text("\(backend.summary) · \(detail)").font(.caption).foregroundStyle(.secondary)
        case .unavailable(let reason, let fix):
            Text("\(reason) \(fix)").font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

/// Vocume as a login item, through macOS's own list (System Settings → General → Login Items).
@MainActor private final class LoginItem: ObservableObject {
    @Published private(set) var isOn = false
    @Published private(set) var needsApproval = false

    init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        isOn = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    func set(_ on: Bool) {
        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        refresh()
    }
}
