import Foundation
import VocumeCore

enum Shell {
    /// The process environment with the usual CLI install locations on `PATH`; apps launched from
    /// Finder get a bare `PATH` that wouldn't find `claude` or `codex`.
    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        env["PATH"] =
            "\(home)/.local/bin:\(home)/.bun/bin:/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        return env
    }

    /// Runs a command to completion and returns its stdout; throws with stderr on a non-zero exit.
    static func run(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment()
        // stderr goes to a file: chatty CLIs could fill a pipe and deadlock us while we read stdout.
        let errors = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: errors.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: errors) }
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = try FileHandle(forWritingTo: errors)
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let stderr = (try? String(contentsOf: errors, encoding: .utf8)) ?? ""
            throw AnnotationError(
                description: "\(arguments[0]) exited \(process.terminationStatus): \(stderr.suffix(500))"
            )
        }
        return String(decoding: data, as: UTF8.self)
    }
}
