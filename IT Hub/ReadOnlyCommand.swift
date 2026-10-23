import Foundation
import Darwin

nonisolated struct CommandResult: Sendable { let output: String; let code: Int32 }
nonisolated enum ReadOnlyCommand {
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let descriptor = Darwin.open(url.path, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return .init(output: "Could not create private command output", code: -1) }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        defer { try? file.close(); try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"; environment["LANG"] = "C"
        process.environment = environment
        process.standardOutput = file; process.standardError = file
        do {
            try process.run()
            let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
            while process.isRunning && ContinuousClock.now < deadline { Thread.sleep(forTimeInterval: 0.1) }
            if process.isRunning {
                // Process launches the child as its own process-group leader, so signalling the
                // group also stops anything a shell script spawned (background jobs, pipelines).
                let group = process.processIdentifier
                kill(-group, SIGTERM)
                Thread.sleep(forTimeInterval: 0.2)
                kill(-group, SIGKILL)
                process.waitUntilExit()
                let groupDeadline = ContinuousClock.now.advanced(by: .seconds(2))
                while killpg(group, 0) == 0 && ContinuousClock.now < groupDeadline { Thread.sleep(forTimeInterval: 0.05) }
                return .init(output: (try? String(contentsOf: url, encoding: .utf8)) ?? "", code: -2)
            }
            process.waitUntilExit()
            let data = try Data(contentsOf: url)
            return .init(output: String(decoding: data, as: UTF8.self), code: process.terminationStatus)
        } catch { return .init(output: error.localizedDescription, code: -1) }
    }
}
