import Foundation
import VocumeCore

/// The user's AI choices (stored in UserDefaults) plus what auto-detection found on this Mac.
@MainActor final class AISettings: ObservableObject {
    static let shared = AISettings()

    /// Master switch: off hides the AI bar entirely.
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled) }
    }
    /// Providers the user allows; a provider is offered only when allowed *and* detected as ready.
    @Published var allowed: Set<AIBackend> {
        didSet { defaults.set(allowed.map(\.rawValue).sorted(), forKey: Keys.allowed) }
    }
    @Published var ollamaModel: String {
        didSet { defaults.set(ollamaModel, forKey: Keys.ollamaModel) }
    }
    @Published private(set) var status: [AIBackend: ProviderStatus] = [:]
    @Published private(set) var ollamaModels: [String] = []
    /// Providers whose detection is still running (Settings shows a spinner; the editor's bar keeps
    /// the last known result so open windows don't flicker on every re-check).
    @Published private(set) var checking: Set<AIBackend> = []

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let enabled = "aiEnabled"
        static let allowed = "aiAllowedProviders"
        static let ollamaModel = "aiOllamaModel"
    }

    private init() {
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        let stored = defaults.stringArray(forKey: Keys.allowed)
        allowed = Set((stored ?? AIBackend.allCases.map(\.rawValue)).compactMap(AIBackend.init(rawValue:)))
        ollamaModel = defaults.string(forKey: Keys.ollamaModel) ?? ""
    }

    /// Providers to offer in the editor, in a stable order.
    var usable: [AIBackend] {
        guard isEnabled else { return [] }
        return AIBackend.allCases.filter { allowed.contains($0) && status[$0]?.isReady == true }
    }

    func isAllowed(_ backend: AIBackend) -> Bool { allowed.contains(backend) }

    /// Whether a pre-started Claude process is worth keeping: AI on, Claude allowed, and not known
    /// to be missing or signed out.
    var wantsWarmClaude: Bool {
        guard isEnabled, isAllowed(.claude) else { return false }
        if case .unavailable = status[.claude] { return false }
        return true
    }

    func setAllowed(_ backend: AIBackend, _ on: Bool) {
        if on { allowed.insert(backend) } else { allowed.remove(backend) }
    }

    /// Re-runs detection for every provider, in parallel and off the main actor. A provider keeps
    /// its last known status until the new result arrives.
    func refresh() {
        for backend in AIBackend.allCases where !checking.contains(backend) {
            checking.insert(backend)
            if status[backend] == nil { status[backend] = .checking }
            Task.detached {
                let result = await backend.detect()
                let models = backend == .ollama ? await Ollama.visionModels() ?? [] : []
                await MainActor.run { self.apply(result, models: models, for: backend) }
            }
        }
    }

    private func apply(_ result: ProviderStatus, models: [String], for backend: AIBackend) {
        checking.remove(backend)
        status[backend] = result
        guard backend == .ollama else { return }
        ollamaModels = models
        if !models.contains(ollamaModel) { ollamaModel = models.first ?? "" }
    }
}
