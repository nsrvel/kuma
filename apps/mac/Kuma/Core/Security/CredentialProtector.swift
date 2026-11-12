import Foundation

/// Encrypts provider credentials for persistence/export; fails closed (no plaintext fallback).
public enum CredentialProtector {
    public nonisolated static func encryptForStorage(_ plainText: String) throws -> String {
        try CryptoVault.shared.encrypt(plainText: plainText)
    }
}
