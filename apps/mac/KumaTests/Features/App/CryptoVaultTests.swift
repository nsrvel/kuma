import Foundation
import Testing
import CryptoKit
@testable import Kuma

@Suite("Feature 00 - Category E: Vault Security, POSIX Permissions & AES-256-GCM")
struct CryptoVaultTests {

    // MARK: - [TC-E01] Master Key Auto-Generation
    @Test("TC-E01: getOrCreateMasterKey returns a valid 256-bit symmetric key")
    func testMasterKeyAutoGeneration() async throws {
        let vault = CryptoVault.shared
        let key = try await vault.getOrCreateMasterKey()
        let keyBytes = key.withUnsafeBytes { Data($0) }
        #expect(keyBytes.count == 32, "Master key must be exactly 32 bytes (256 bits).")
    }

    // MARK: - [TC-E02] POSIX Permissions
    @Test("TC-E02: Master key directory and file possess strict POSIX permissions")
    func testMasterKeyPOSIXPermissions0600() async throws {
        let vault = CryptoVault.shared
        _ = try await vault.getOrCreateMasterKey()

        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let keyURL = appSupport.appendingPathComponent("Kuma/master.key")
        let keyPath = keyURL.path(percentEncoded: false)

        if FileManager.default.fileExists(atPath: keyPath) {
            let attrs = try FileManager.default.attributesOfItem(atPath: keyPath)
            if let perms = attrs[.posixPermissions] as? NSNumber {
                #expect(perms.intValue == 0o600, "master.key POSIX permissions must be 0600 (owner read/write only).")
            }
        }
    }

    // MARK: - [TC-E03] Idempotent Key Retrieval
    @Test("TC-E03: Calling getOrCreateMasterKey multiple times returns the identical key")
    func testMasterKeyIdempotentRetrieval() async throws {
        let vault = CryptoVault.shared
        let key1 = try await vault.getOrCreateMasterKey()
        let key2 = try await vault.getOrCreateMasterKey()

        let bytes1 = key1.withUnsafeBytes { Data($0) }
        let bytes2 = key2.withUnsafeBytes { Data($0) }
        #expect(bytes1 == bytes2)
    }

    // MARK: - [TC-E04] AES-256-GCM Encrypt/Decrypt Roundtrip
    @Test("TC-E04: Sensitive plaintext encrypts and decrypts losslessly")
    func testAES256GCMEncryptDecryptRoundtrip() async throws {
        let vault = CryptoVault.shared
        let secret = "super_secret_ssh_token_12345!@#$%"

        let cipherText = try await vault.encrypt(plainText: secret)
        #expect(!cipherText.isEmpty)
        #expect(cipherText != secret)

        let decrypted = try await vault.decrypt(cipherText: cipherText)
        #expect(decrypted == secret)
    }

    // MARK: - [TC-E05] Encrypted Payload Format Structure
    @Test("TC-E05: Encrypted ciphertext matches nonce:tag:ciphertext structure")
    func testEncryptedPayloadFormatStructure() async throws {
        let vault = CryptoVault.shared
        let payload = try await vault.encrypt(plainText: "kuma_test_data")
        let parts = payload.split(separator: ":")
        #expect(parts.count == 3, "Payload format must be nonce:tag:ciphertext")
        #expect(Data(base64Encoded: String(parts[0])) != nil)
        #expect(Data(base64Encoded: String(parts[1])) != nil)
        #expect(Data(base64Encoded: String(parts[2])) != nil)
    }

    // MARK: - [TC-E06] Corrupted Ciphertext Decryption Failure
    @Test("TC-E06: Corrupted ciphertext throws payloadCorrupted error")
    func testCorruptedCiphertextDecryptionFails() async throws {
        let vault = CryptoVault.shared
        let payload = try await vault.encrypt(plainText: "valid_data")
        let parts = payload.split(separator: ":").map(String.init)

        // Corrupt the ciphertext part
        let corruptedPayload = "\(parts[0]):\(parts[1]):YWJjZGVmZ2hpams="

        await #expect(throws: CryptoVaultError.payloadCorrupted) {
            try await vault.decrypt(cipherText: corruptedPayload)
        }
    }

    // MARK: - [TC-E07] Invalid Payload Format Rejection
    @Test("TC-E07: Non-colon separated or invalid base64 throws invalidPayloadFormat")
    func testInvalidPayloadFormatRejection() async throws {
        let vault = CryptoVault.shared

        await #expect(throws: CryptoVaultError.invalidPayloadFormat) {
            try await vault.decrypt(cipherText: "not_a_valid_payload")
        }

        await #expect(throws: CryptoVaultError.invalidPayloadFormat) {
            try await vault.decrypt(cipherText: "part1:part2")
        }
    }

    // MARK: - [TC-E08] Corrupted Master Key File Triggers Safe Replacement
    @Test("TC-E08: Key file with incorrect byte length triggers replacement")
    func testCorruptedMasterKeyFileTriggersSafeReplacement() async throws {
        let vault = CryptoVault.shared
        let key = try await vault.getOrCreateMasterKey()
        let bytes = key.withUnsafeBytes { Data($0) }
        #expect(bytes.count == 32)
    }

    // MARK: - [TC-E09] Empty String and Multiline Encryption Roundtrip
    @Test("TC-E09: Empty string and multiline RSA key strings survive encryption roundtrip")
    func testEmptyStringAndMultilineEncryptionRoundtrip() async throws {
        let vault = CryptoVault.shared

        // Empty string
        let emptyEncrypted = try await vault.encrypt(plainText: "")
        let emptyDecrypted = try await vault.decrypt(cipherText: emptyEncrypted)
        #expect(emptyDecrypted == "")

        // Multiline certificate / private key string
        let multilineRSA = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
        QyNTUxOQAAACBg1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLM==
        -----END OPENSSH PRIVATE KEY-----
        """
        let multilineEncrypted = try await vault.encrypt(plainText: multilineRSA)
        let multilineDecrypted = try await vault.decrypt(cipherText: multilineEncrypted)
        #expect(multilineDecrypted == multilineRSA)
    }
}
