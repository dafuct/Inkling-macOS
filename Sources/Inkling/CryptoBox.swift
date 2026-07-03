import CryptoKit
import Foundation
import Security

/// Fetches or creates the app's 256-bit symmetric key in the Keychain. Marked
/// ThisDeviceOnly so encrypted typing history never syncs off this Mac.
///
/// Main-thread only (like the stores that use it): concurrent getOrCreate()
/// calls could each mint a key with the last write winning, orphaning data
/// sealed under the loser.
enum KeychainKey {
    private static let service = "app.inkling.inputstore"
    private static let account = "aesKey"

    static func getOrCreate() -> SymmetricKey {
        if let existing = load() { return existing }
        let key = SymmetricKey(size: .bits256)
        save(key)
        // Verify the key actually persisted: if the Keychain write failed, a
        // fresh key would be generated next launch and everything sealed under
        // this one would be lost. Prefer the persisted key as truth.
        if let persisted = load() { return persisted }
        NSLog("Inkling: WARNING — Keychain save failed; encryption key is memory-only this session")
        return key
    }

    private static func load() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    private static func save(_ key: SymmetricKey) {
        let data = key.withUnsafeBytes { Data(Array($0)) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        SecItemDelete(query as CFDictionary)   // avoid duplicate-item errors
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("Inkling: Keychain SecItemAdd failed (status \(status))")
        }
    }
}

/// AES-GCM seal/open with a given key. `seal` returns the combined
/// nonce+ciphertext+tag blob; `open` reverses it.
enum CryptoBox {
    enum CryptoBoxError: Error { case sealProducedNoCombined }

    static func seal(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw CryptoBoxError.sealProducedNoCombined }
        return combined
    }

    static func open(_ ciphertext: Data, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: key)
    }
}
