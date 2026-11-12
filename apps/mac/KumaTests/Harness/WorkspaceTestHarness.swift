import Foundation
import GRDB
import AppKit
@testable import Kuma

/// Isolated test harness for Feature 03: Workspace.
/// Provides an isolated in-memory AppDatabase, isolated UserDefaults suite,
/// and isolated temporary workspace images directory for zero-side-effect testing.
@MainActor
public final class WorkspaceTestHarness {
    public let suiteName: String
    public let userDefaults: UserDefaults
    public let databaseQueue: DatabaseQueue
    public let repository: WorkspaceRepository
    public let tempImagesDir: URL

    private var createdFilePaths: [String] = []
    private let fileManager = FileManager.default

    public init(suiteName: String = "kuma.tests.workspace.\(UUID().uuidString)") {
        self.suiteName = suiteName
        self.userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.userDefaults.removePersistentDomain(forName: suiteName)

        // Setup In-Memory SQLite Database with Foreign Keys and Production Migrations
        var config = Configuration()
        config.qos = .userInitiated
        config.prepareDatabase { db in
            try? db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let queue = try! DatabaseQueue(configuration: config)

        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_production_schema") { db in
            try db.create(table: "workspace") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("imagePath", .text)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "service") { t in
                t.column("id", .text).primaryKey()
                t.column("workspaceID", .text).notNull().references("workspace", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("isDisabled", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }
        try! migrator.migrate(queue)

        self.databaseQueue = queue
        self.repository = WorkspaceRepository(dbWriter: queue)

        // Setup temporary directory for images
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("kuma_tests_img_\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.tempImagesDir = tempDir
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempImagesDir)
        for path in createdFilePaths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    public func cleanup() {
        userDefaults.removePersistentDomain(forName: suiteName)
        try? fileManager.removeItem(at: tempImagesDir)
        for path in createdFilePaths {
            try? fileManager.removeItem(atPath: path)
        }
        createdFilePaths.removeAll()
        WorkspaceImageStore.shared.clearCache()
    }

    /// Creates a dummy valid PNG file with specific dimensions for test cases.
    @discardableResult
    public func createSampleImage(width: Int = 100, height: Int = 100) -> URL {
        let fileURL = tempImagesDir.appendingPathComponent("\(UUID().uuidString).png")
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!

        let data = rep.representation(using: .png, properties: [:])!
        try! data.write(to: fileURL, options: .atomic)
        createdFilePaths.append(fileURL.path(percentEncoded: false))
        return fileURL
    }

    /// Creates a text dummy file pretending to be an image
    @discardableResult
    public func createCorruptedImageFile() -> URL {
        let fileURL = tempImagesDir.appendingPathComponent("\(UUID().uuidString)_corrupt.png")
        let data = "not a valid image content".data(using: .utf8)!
        try! data.write(to: fileURL, options: .atomic)
        createdFilePaths.append(fileURL.path(percentEncoded: false))
        return fileURL
    }
}
