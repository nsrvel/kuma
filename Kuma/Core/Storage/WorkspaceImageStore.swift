import AppKit
import Foundation
import ImageIO
import os

/// Hardware-accelerated ImageIO Downsampler & Managed Local Image Store.
/// `@unchecked Sendable` because NSCache is internally thread-safe and all
/// file operations use atomic writes. All public methods are `nonisolated`
/// so they can safely be called from GRDB background closures.
public nonisolated final class WorkspaceImageStore: @unchecked Sendable {
    private let logger = Logger(subsystem: "lokastudio.kuma", category: "WorkspaceImageStore")
    public static let shared = WorkspaceImageStore()

    // NSCache is thread-safe per Apple's docs. Stored as nonisolated(unsafe)
    // because our class is @unchecked Sendable and we guarantee safe usage.
    nonisolated(unsafe) private let cache = NSCache<NSString, NSImage>()
    private let revisionLock = NSLock()
    nonisolated(unsafe) private var imageRevisions: [String: UInt64] = [:]

    private init() {
        cache.countLimit = 100
    }

    // MARK: - Internal Storage Directory

    /// Resolves the dedicated workspace images directory inside Application Support
    public nonisolated func imagesDirectoryURL() -> URL {
        do {
            let fm = FileManager.default
            let appSupportURL = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dirURL = appSupportURL.appendingPathComponent("Kuma/Workspaces/Images", isDirectory: true)
            let dirPath = dirURL.path(percentEncoded: false)
            if !fm.fileExists(atPath: dirPath) {
                try fm.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
            }
            return dirURL
        } catch {
            self.logger.error("Failed to create workspace images directory: \(error.localizedDescription)")
            return FileManager.default.temporaryDirectory
        }
    }

    // MARK: - Save / Copy Image to App Storage

    /// Copies an external image from source URL into Kuma's managed internal folder.
    /// Returns the permanent relative filename (e.g. "{workspaceID}.png").
    public nonisolated func saveWorkspaceImage(from sourceURL: URL, workspaceID: UUID) -> String? {
        let destFileName = "\(workspaceID.uuidString).png"
        let destURL = imagesDirectoryURL().appendingPathComponent(destFileName)
        let destPath = destURL.path(percentEncoded: false)
        let sourcePath = sourceURL.path(percentEncoded: false)
        let fm = FileManager.default

        do {
            if fm.fileExists(atPath: destPath) {
                try fm.removeItem(at: destURL)
            }

            guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
                self.logger.error("Failed to read image source at \(sourcePath)")
                return nil
            }

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512
            ]

            guard let thumbnailRef = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                self.logger.error("Failed to generate thumbnail for save from \(sourcePath)")
                return nil
            }

            let bitmapRep = NSBitmapImageRep(cgImage: thumbnailRef)
            guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
                self.logger.error("Failed to encode image to PNG")
                return nil
            }

            try pngData.write(to: destURL, options: .atomic)
            evictCache(for: destFileName)
            self.logger.info("Saved workspace image for \(workspaceID) to \(destPath)")
            return destFileName
        } catch {
            self.logger.error("Failed to save workspace image: \(error.localizedDescription)")
            return nil
        }
    }

    /// Saves base64 string data from a backup import into local file storage
    public nonisolated func saveBase64Image(_ base64String: String, workspaceID: UUID) -> String? {
        guard let data = Data(base64Encoded: base64String) else { return nil }
        let destFileName = "\(workspaceID.uuidString).png"
        let destURL = imagesDirectoryURL().appendingPathComponent(destFileName)

        do {
            try data.write(to: destURL, options: .atomic)
            evictCache(for: destFileName)
            return destFileName
        } catch {
            self.logger.error("Failed to write base64 image to disk: \(error.localizedDescription)")
            return nil
        }
    }

    /// Loads the raw base64 string representation for export backups
    public nonisolated func loadBase64Image(for fileNameOrPath: String) -> String? {
        let fileURL = resolveURL(for: fileNameOrPath)
        let filePath = fileURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: filePath),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return data.base64EncodedString()
    }

    // MARK: - Fast Hardware-Downsampled Loading

    /// Loads and downsamples a workspace avatar image to target size using ImageIO & NSCache.
    public nonisolated func thumbnail(for fileNameOrPath: String, maxDimension: CGFloat = 128) -> NSImage? {
        let fileURL = resolveURL(for: fileNameOrPath)
        let filePath = fileURL.path(percentEncoded: false)
        let cacheKey = cacheKey(for: filePath, maxDimension: maxDimension)

        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        guard FileManager.default.fileExists(atPath: filePath) else {
            return nil
        }

        // Load from bytes so ImageIO does not serve a stale decoded image after the file is replaced in place.
        guard let data = try? Data(contentsOf: fileURL),
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]

        guard let thumbnailRef = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }

        let thumbnail = NSImage(cgImage: thumbnailRef, size: NSSize(width: maxDimension, height: maxDimension))
        cache.setObject(thumbnail, forKey: cacheKey)
        return thumbnail
    }

    private nonisolated func cacheKey(for filePath: String, maxDimension: CGFloat) -> NSString {
        let revision = revision(forFilePath: filePath)
        return "\(filePath)-\(Int(maxDimension))-r\(revision)" as NSString
    }

    private nonisolated func revision(forFilePath filePath: String) -> UInt64 {
        revisionLock.lock()
        defer { revisionLock.unlock() }
        return imageRevisions[filePath] ?? 0
    }

    /// Bumps revision so every thumbnail size misses NSCache after the on-disk file changes.
    private nonisolated func evictCache(for fileNameOrPath: String) {
        let filePath = resolveURL(for: fileNameOrPath).path(percentEncoded: false)
        revisionLock.lock()
        imageRevisions[filePath] = (imageRevisions[filePath] ?? 0) + 1
        revisionLock.unlock()
    }

    /// Resolves filename or legacy absolute path to a valid URL
    public nonisolated func resolveURL(for fileNameOrPath: String) -> URL {
        if fileNameOrPath.hasPrefix("/") {
            return URL(fileURLWithPath: fileNameOrPath)
        }
        return imagesDirectoryURL().appendingPathComponent(fileNameOrPath)
    }

    /// Deletes an image file when workspace is deleted
    public nonisolated func deleteImage(for fileNameOrPath: String) {
        let fileURL = resolveURL(for: fileNameOrPath)
        try? FileManager.default.removeItem(at: fileURL)
        evictCache(for: fileNameOrPath)
    }

    /// Clears the memory cache
    public nonisolated func clearCache() {
        revisionLock.lock()
        imageRevisions.removeAll()
        revisionLock.unlock()
        cache.removeAllObjects()
    }
}
