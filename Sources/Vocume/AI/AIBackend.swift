import Foundation
import UniformTypeIdentifiers
import VocumeCore

/// Who answers annotation requests: the user's own Claude Code or Codex login, or a local Ollama
/// vision model. No API keys anywhere.
enum AIBackend: String, CaseIterable, Identifiable, Sendable {
    case claude, codex, ollama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .ollama: "Ollama"
        }
    }

    /// What it runs on, for Settings.
    var summary: String {
        switch self {
        case .claude: "Your Claude Code login"
        case .codex: "Your Codex (ChatGPT) login"
        case .ollama: "A vision model running locally"
        }
    }

    /// Checks whether this provider is usable right now, using each tool's own login check.
    /// Blocking; call off the main actor.
    func detect() async -> ProviderStatus {
        switch self {
        case .claude:
            guard let result = try? Shell.capture(["claude", "auth", "status"]) else {
                return ProviderCheck.claude(exitCode: 127, output: "")
            }
            return ProviderCheck.claude(exitCode: result.status, output: result.stdout)
        case .codex:
            guard let result = try? Shell.capture(["codex", "login", "status"]) else {
                return ProviderCheck.codex(exitCode: 127, output: "")
            }
            return ProviderCheck.codex(exitCode: result.status, output: result.stdout + result.stderr)
        case .ollama:
            return ProviderCheck.ollama(visionModels: await Ollama.visionModels())
        }
    }

    /// Sends the prompt with the screenshot and returns the raw reply text.
    /// - Parameters:
    ///   - claude: a pre-started session to use (Claude only).
    ///   - codex: the process to run Codex in, so the caller can terminate it (Codex only).
    ///   - ollamaModel: the local model to use (Ollama only).
    func ask(
        _ prompt: String,
        image: URL,
        claude: ClaudeSession?,
        codex: Process = Process(),
        ollamaModel: String = ""
    ) async throws -> String {
        switch self {
        case .claude:
            // Original resolution (quality over speed): the CLI downsizes only if the model needs it.
            let mediaType = UTType(filenameExtension: image.pathExtension)?.preferredMIMEType ?? "image/png"
            return try (claude ?? ClaudeSession()).ask(prompt, image: try imageData(image), mediaType: mediaType)
        case .codex:
            return try Codex.ask(prompt, image: image, process: codex)
        case .ollama:
            guard !ollamaModel.isEmpty else {
                throw AnnotationError(description: "Choose an Ollama model in Settings.")
            }
            return try await Ollama.chat(
                model: ollamaModel,
                system: AnnotationPrompt.systemPrompt,
                prompt: prompt,
                image: try imageData(image)
            )
        }
    }

    private func imageData(_ url: URL) throws -> Data {
        guard let data = try? Data(contentsOf: url) else {
            throw AnnotationError(description: "Couldn't read \(url.lastPathComponent)")
        }
        return data
    }
}
