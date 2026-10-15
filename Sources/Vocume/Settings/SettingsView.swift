import SwiftUI
import VocumeCore

/// Settings: capture shortcuts, whether to use AI at all, and which detected providers to offer.
struct SettingsView: View {
    @ObservedObject var settings: AISettings

    var body: some View {
        Form {
            CaptureSettingsSection()

            Section {
                Toggle(isOn: $settings.isEnabled) {
                    Text("Annotate with AI")
                    Text(
                        "Describe the markup and let an AI place the marks. Uses apps you're already signed in to — no API keys."
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
                HStack {
                    Text("Detected automatically on this Mac.")
                        .foregroundStyle(.secondary)
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
        .formStyle(.grouped)
        .frame(width: 520)
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
