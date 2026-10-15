import Foundation
import VocumeCore

/// A `claude` process started ahead of time, waiting for exactly one request on stdin.
///
/// Starting it when the editor opens hides about a second of CLI startup without costing quality.
/// `--safe-mode` skips plugins, hooks and MCP servers but keeps the subscription login (`--bare`
/// would need an API key). The image is sent inline, so Claude needs no tools and no extra turn.
final class ClaudeSession: Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()

    var isRunning: Bool { process.isRunning }

    init() {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "claude", "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
            "--safe-mode", "--tools", "", "--no-session-persistence",
            "--system-prompt", AnnotationPrompt.systemPrompt,
        ]
        process.environment = Shell.environment()
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    deinit {
        cancel()
    }

    /// Stops the process; a pending `ask` then fails, and its result is discarded by the caller.
    func cancel() {
        if process.isRunning { process.terminate() }
    }

    /// Sends one user message (image + text) and waits for the `result` event.
    func ask(_ prompt: String, image: Data, mediaType: String) throws -> String {
        guard process.isRunning else {
            throw AnnotationError(description: "claude didn't start (is it installed and logged in?)")
        }
        let message: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": [
                    [
                        "type": "image",
                        "source": ["type": "base64", "media_type": mediaType, "data": image.base64EncodedString()],
                    ],
                    ["type": "text", "text": prompt],
                ],
            ],
        ]
        try input.fileHandleForWriting.write(
            contentsOf: try JSONSerialization.data(withJSONObject: message) + Data("\n".utf8))
        defer { try? input.fileHandleForWriting.close() }

        var buffer = Data()
        while true {  // one JSON event per line; stop at the result
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { throw AnnotationError(description: "claude exited without a result") }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[..<newline]
                buffer = Data(buffer[(newline + 1)...])
                guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                    event["type"] as? String == "result"
                else { continue }
                if event["is_error"] as? Bool == true {
                    throw AnnotationError(description: "claude: \(event["result"] ?? event)")
                }
                return event["result"] as? String ?? ""
            }
        }
    }
}
