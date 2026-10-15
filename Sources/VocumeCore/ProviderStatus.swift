import Foundation

/// Whether an AI provider can be used right now, as found by auto-detection.
public enum ProviderStatus: Equatable, Sendable {
    case checking
    /// Usable. `detail` says how (e.g. the signed-in account).
    case ready(detail: String)
    /// Not usable; `fix` tells the user what to do about it.
    case unavailable(reason: String, fix: String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

/// Turns the output of each CLI's own login check into a `ProviderStatus`.
public enum ProviderCheck {
    /// `env` exits with 127 when the command isn't on the PATH.
    static let commandNotFound: Int32 = 127

    /// From `claude auth status`, which prints JSON such as
    /// `{"loggedIn": true, "authMethod": "claude.ai", "email": "…", "subscriptionType": "team"}`.
    public static func claude(exitCode: Int32, output: String) -> ProviderStatus {
        if exitCode == commandNotFound {
            return .unavailable(reason: "Claude Code isn't installed.", fix: "Install it from claude.com/claude-code.")
        }
        let notSignedIn = ProviderStatus.unavailable(
            reason: "Not signed in.",
            fix: "Run `claude` in Terminal and sign in (or update Claude Code)."
        )
        guard exitCode == 0,
            let start = output.firstIndex(of: "{"),
            let json = try? JSONSerialization.jsonObject(with: Data(output[start...].utf8)) as? [String: Any],
            json["loggedIn"] as? Bool == true
        else { return notSignedIn }
        let plan = (json["subscriptionType"] as? String).map { " (\($0.capitalized) plan)" } ?? ""
        if let email = json["email"] as? String, !email.isEmpty {
            return .ready(detail: "Signed in as \(email)\(plan)")
        }
        return .ready(detail: "Signed in\(plan)")
    }

    /// From `codex login status`, which prints e.g. "Logged in using ChatGPT".
    public static func codex(exitCode: Int32, output: String) -> ProviderStatus {
        if exitCode == commandNotFound {
            return .unavailable(
                reason: "Codex isn't installed.", fix: "Install it with `npm install -g @openai/codex`.")
        }
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard exitCode == 0, text.localizedCaseInsensitiveContains("logged in"),
            !text.localizedCaseInsensitiveContains("not logged in")
        else { return .unavailable(reason: "Not signed in.", fix: "Run `codex login` in Terminal.") }
        return .ready(detail: text)
    }

    /// From Ollama's installed models: usable only with at least one vision model.
    public static func ollama(visionModels: [String]?) -> ProviderStatus {
        guard let visionModels else {
            return .unavailable(reason: "Ollama isn't running.", fix: "Install it from ollama.com and start it.")
        }
        guard !visionModels.isEmpty else {
            return .unavailable(
                reason: "No vision model installed.",
                fix: "Run `ollama pull qwen2.5vl` (or another model that can see images)."
            )
        }
        let count = visionModels.count
        return .ready(detail: "\(count) vision model\(count == 1 ? "" : "s") installed")
    }
}
