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
    /// Pass `process` to keep a handle for terminating it from elsewhere.
    static func run(_ arguments: [String], in directory: URL, process: Process = Process()) throws -> String {
        let result = try capture(arguments, in: directory, process: process)
        guard result.status == 0 else {
            throw AnnotationError(description: "\(arguments[0]) exited \(result.status): \(result.stderr.suffix(500))")
        }
        return result.stdout
    }

    /// Runs a command to completion and returns its exit status and output, whatever the status.
    /// `env` exits with 127 when the command isn't installed.
    static func capture(
        _ arguments: [String],
        in directory: URL = FileManager.default.temporaryDirectory,
        process: Process = Process()
    ) throws -> (status: Int32, stdout: String, stderr: String) {
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
        let stderr = (try? String(contentsOf: errors, encoding: .utf8)) ?? ""
        return (process.terminationStatus, String(decoding: data, as: UTF8.self), stderr)
    }
}
