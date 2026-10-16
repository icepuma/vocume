import Foundation
import VocumeCore

/// Runs `codex exec` once per request.
enum Codex {
    /// Uses the configured model and reasoning effort (quality over speed). Only MCP servers are
    /// skipped: this task never uses them and starting them costs seconds.
    static func ask(_ prompt: String, image: URL, process: Process = Process()) throws -> String {
        let lastMessage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        // The reply is checked against the marks' schema (OpenAI's strict form), so it is always
        // well-formed JSON.
        let schema = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try AnnotationPrompt.strictReplySchema.write(to: schema, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: lastMessage)
            try? FileManager.default.removeItem(at: schema)
        }
        let stdout = try Shell.run(
            [
                "codex", "exec", "--skip-git-repo-check", "-s", "read-only", "-c", "mcp_servers={}",
                "--image=\(image.path)", "--output-last-message=\(lastMessage.path)",
                "--output-schema=\(schema.path)", prompt,
            ],
            in: image.deletingLastPathComponent(),
            process: process
        )
        return (try? String(contentsOf: lastMessage, encoding: .utf8)) ?? stdout
    }
}
