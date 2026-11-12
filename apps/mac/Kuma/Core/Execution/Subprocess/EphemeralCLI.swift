import Foundation
import os

/// Short-lived `Process` invocations (compose, kubectl preflight/list). Never use `ProcessRegistry`.
enum EphemeralCLI {
    struct Result: Sendable {
        let terminationStatus: Int32
        let stdout: String
        let stderr: String
    }

    enum StdioMode: Sendable {
        /// Single merged stream (compose stdout+stderr) captured to memory.
        case merged
        /// Read stdout and stderr to memory (kubectl helpers).
        case captureSeparated
        /// Drain pipes without retaining output.
        case discard
    }

    @discardableResult
    static func run(
        executablePath: String,
        arguments: [String],
        workingDirectory: String? = nil,
        timeout: TimeInterval?,
        stdio: StdioMode
    ) async throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let workingDirectory, !workingDirectory.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        switch stdio {
        case .merged:
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let captured = OSAllocatedUnfairLock(initialState: "")
            let ingest: @Sendable (String) -> Void = { chunk in
                captured.withLock { $0 += chunk }
            }
            attachDrain(pipe: pipe, onChunk: ingest)
            try process.run()
            let completed = await SubprocessWait.waitForExit(of: process, timeout: timeout)
            pipe.fileHandleForReading.readabilityHandler = nil
            let trailing = pipe.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: trailing, encoding: .utf8), !text.isEmpty {
                ingest(text)
            }
            try? pipe.fileHandleForReading.close()
            if let timeout, !completed {
                throw ServiceExecutionError.processFailed("Command timed out after \(Int(timeout))s")
            }
            let streamText = captured.withLock { $0 }
            return Result(terminationStatus: process.terminationStatus, stdout: "", stderr: streamText)

        case .captureSeparated:
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            try process.run()
            async let stdoutData = Task.detached {
                stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            }.value
            async let stderrData = Task.detached {
                stderrPipe.fileHandleForReading.readDataToEndOfFile()
            }.value
            _ = await withTaskCancellationHandler {
                await SubprocessWait.waitForExit(of: process, timeout: timeout)
            } onCancel: {
                if process.isRunning {
                    process.terminate()
                }
            }
            let outBytes = await stdoutData
            let errBytes = await stderrData
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
            if let timeout, process.isRunning {
                process.terminate()
                throw ServiceExecutionError.processFailed("Command timed out after \(Int(timeout))s")
            }
            return Result(
                terminationStatus: process.terminationStatus,
                stdout: String(data: outBytes, encoding: .utf8) ?? "",
                stderr: String(data: errBytes, encoding: .utf8) ?? ""
            )

        case .discard:
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            attachDrain(pipe: stdoutPipe, onChunk: { _ in })
            attachDrain(pipe: stderrPipe, onChunk: { _ in })
            try process.run()
            let completed = await SubprocessWait.waitForExit(of: process, timeout: timeout)
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            _ = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            _ = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
            if let timeout, !completed {
                throw ServiceExecutionError.processFailed("Command timed out after \(Int(timeout))s")
            }
            return Result(terminationStatus: process.terminationStatus, stdout: "", stderr: "")
        }
    }

    private static func attachDrain(pipe: Pipe, onChunk: @escaping @Sendable (String) -> Void) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8) {
                onChunk(text)
            }
        }
    }
}
