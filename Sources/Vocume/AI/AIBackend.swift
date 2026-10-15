import Foundation
import UniformTypeIdentifiers
import VocumeCore

/// Which CLI answers annotation requests. Both use the user's own subscription login.
enum AIBackend: String, CaseIterable, Identifiable {
    case claude, codex

    var id: String { rawValue }
    var displayName: String { self == .claude ? "Claude" : "Codex" }

    /// Sends the prompt with the screenshot and returns the raw reply text.
    /// - Parameter claude: a pre-started session to use (Claude only).
    func ask(_ prompt: String, image: URL, claude: ClaudeSession?) throws -> String {
        switch self {
        case .claude:
            // Original resolution (quality over speed): the CLI downsizes only if the model needs it.
            guard let data = try? Data(contentsOf: image) else {
                throw AnnotationError(description: "Couldn't read \(image.lastPathComponent)")
            }
            let mediaType = UTType(filenameExtension: image.pathExtension)?.preferredMIMEType ?? "image/png"
            return try (claude ?? ClaudeSession()).ask(prompt, image: data, mediaType: mediaType)
        case .codex:
            return try Codex.ask(prompt, image: image)
        }
    }
}
