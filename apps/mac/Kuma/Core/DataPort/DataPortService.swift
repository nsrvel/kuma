import Foundation
import AppKit
import os

public nonisolated enum DataPortService {
    static let logger = Logger(subsystem: "lokastudio.kuma", category: "DataPortService")
    public static let currentVersion = 1

    public enum DataPortError: Error, LocalizedError, Sendable {
        case unsupportedFutureVersion(backupVersion: Int, currentVersion: Int)

        public var errorDescription: String? {
            switch self {
            case .unsupportedFutureVersion(let backup, let current):
                return "The backup file was created by a newer version of Kuma (Backup v\(backup), App v\(current)). Please update Kuma."
            }
        }
    }
}
