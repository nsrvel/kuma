import Foundation
import Darwin

enum RunSpool: Sendable {
    private nonisolated(unsafe) static let maxSpoolBytes = 8 * 1024 * 1024

    nonisolated static func directoryURL() -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("kuma-run", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    nonisolated static func url(for serviceID: UUID) -> URL {
        directoryURL().appendingPathComponent("\(serviceID.uuidString).out")
    }

    nonisolated static func prepare(for serviceID: UUID) throws -> Int32 {
        let path = url(for: serviceID).path
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return fd
    }

    nonisolated static func openAppendFD(for serviceID: UUID) throws -> Int32 {
        let path = url(for: serviceID).path
        let fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        truncateIfNeeded(path: path)
        return fd
    }

    nonisolated static func remove(for serviceID: UUID) {
        try? FileManager.default.removeItem(at: url(for: serviceID))
    }

    nonisolated static func purgeAll() {
        let dir = directoryURL()
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for item in items { try? FileManager.default.removeItem(at: item) }
    }

    nonisolated static func tail(for serviceID: UUID, maxBytes: Int = 4096) -> String? {
        let path = url(for: serviceID).path
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        guard !data.isEmpty else { return nil }
        let slice = data.suffix(maxBytes)
        let text = String(data: slice, encoding: .utf8) ?? ""
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(8).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func truncateIfNeeded(path: String) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int,
              size > maxSpoolBytes else { return }
        // ponytail: single-file truncation drops oldest output; upgrade path is rotated pair of files
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        try? handle.seek(toOffset: UInt64(size - maxSpoolBytes / 2))
        guard let chunk = try? handle.readToEnd() else { return }
        try? handle.close()
        try? Data(chunk).write(to: URL(fileURLWithPath: path))
    }
}
