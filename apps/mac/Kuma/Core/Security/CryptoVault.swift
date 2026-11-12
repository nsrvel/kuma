import Foundation
import CryptoKit
import os

// MARK: - CryptoVaultError

public enum CryptoVaultError: Error, LocalizedError, Sendable, Equatable {
    case invalidUTF8
    case invalidPayloadFormat
    case payloadCorrupted
    case fileAccessError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            return "The data could not be encoded or decoded as UTF-8."
        case .invalidPayloadFormat:
            return "The encrypted payload format is invalid (expected nonce:tag:ciphertext)."
        case .payloadCorrupted:
            return "The encrypted payload is corrupted or authentication tag verification failed."
        case .fileAccessError(let msg):
            return "File access error for master key: \(msg)"
        }
    }
}

// MARK: - CryptoVault (AES-256-GCM MasterKey Utility)

/// Thread-safe class providing AES-256-GCM authenticated encryption for sensitive credentials.
/// Synchronized via OSAllocatedUnfairLock for both sync (DB record encode/decode) and async contexts.
/// Uses a private 256-bit Master Key stored in Application Support with strict POSIX 0600 permissions.
public final nonisolated class CryptoVault: Sendable {
    public nonisolated static let shared = CryptoVault()

    private let logger = Logger(subsystem: "lokastudio.kuma", category: "CryptoVault")
    private let keyLock = OSAllocatedUnfairLock<SymmetricKey?>(initialState: nil)

    public nonisolated init() {}

    // MARK: - Master Key Management

    /// Returns or generates the 256-bit symmetric master key from disk.
    public nonisolated func getOrCreateMasterKey() throws -> SymmetricKey {
        if let existing = keyLock.withLock({ $0 }) {
            return existing
        }

        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folderURL = appSupportURL.appendingPathComponent("Kuma", isDirectory: true)
        let folderPath = folderURL.path(percentEncoded: false)
        if !fileManager.fileExists(atPath: folderPath) {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
        }

        let keyURL = folderURL.appendingPathComponent("master.key", isDirectory: false)
        let keyPath = keyURL.path(percentEncoded: false)

        // 1. Read existing key if present
        if fileManager.fileExists(atPath: keyPath) {
            let keyData = try Data(contentsOf: keyURL)
            if keyData.count == 32 {
                let key = SymmetricKey(data: keyData)
                keyLock.withLock { $0 = key }
                return key
            } else {
                logger.warning("Existing master key file corrupted (length != 32 bytes). Generating a replacement.")
            }
        }

        // 2. Generate a new 256-bit key
        let newKey = SymmetricKey(size: .bits256)
        let rawData = newKey.withUnsafeBytes { Data($0) }

        // Write with 0600 permissions (User read/write only)
        try rawData.write(to: keyURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyPath)

        keyLock.withLock { $0 = newKey }
        logger.info("Successfully generated and secured new 256-bit Master Key at \(keyPath, privacy: .private)")
        return newKey
    }

    // MARK: - Encryption & Decryption API

    /// Encrypts plain text with AES-256-GCM. Returns a compact string `nonceBase64:tagBase64:ciphertextBase64`.
    public nonisolated func encrypt(plainText: String) throws -> String {
        guard let data = plainText.data(using: .utf8) else {
            throw CryptoVaultError.invalidUTF8
        }

        let key = try getOrCreateMasterKey()
        let sealedBox = try AES.GCM.seal(data, using: key)

        let nonceBase64 = Data(sealedBox.nonce).base64EncodedString()
        let tagBase64 = sealedBox.tag.base64EncodedString()
        let cipherBase64 = sealedBox.ciphertext.base64EncodedString()

        return "\(nonceBase64):\(tagBase64):\(cipherBase64)"
    }

    /// Decrypts a compact string payload `nonceBase64:tagBase64:ciphertextBase64` back to plain text.
    public nonisolated func decrypt(cipherText: String) throws -> String {
        let trimmed = cipherText.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.split(separator: ":", omittingEmptySubsequences: false).map(String.init)

        guard components.count == 3,
              let nonceData = Data(base64Encoded: components[0]),
              let tagData = Data(base64Encoded: components[1]),
              let cipherData = components[2].isEmpty ? Data() : Data(base64Encoded: components[2]) else {
            throw CryptoVaultError.invalidPayloadFormat
        }

        let key = try getOrCreateMasterKey()
        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: cipherData, tag: tagData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            guard let result = String(data: decryptedData, encoding: .utf8) else {
                throw CryptoVaultError.invalidUTF8
            }
            return result
        } catch let err as CryptoVaultError {
            throw err
        } catch {
            throw CryptoVaultError.payloadCorrupted
        }
    }
}

