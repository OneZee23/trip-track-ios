import Foundation
import Security

enum KeychainHelper {

    enum KeychainError: Error {
        case saveFailed(OSStatus)
        case loadFailed
        case deleteFailed(OSStatus)
    }

    private static let service = "com.triptrack.keychain"

    static func save(_ data: Data, for key: String) throws {
        delete(key: key)

        // `ThisDeviceOnly` so tokens & identity DO NOT replicate via iCloud
        // Keychain or encrypted device backup. Without this, an attacker who
        // restores a backup of the user's iPhone (including via known passcode-
        // bypass attacks at low PIN entropy) inherits a valid session.
        // `kSecAttrSynchronizable = false` is the explicit "no iCloud sync"
        // belt to the suspenders — defense-in-depth for future iOS versions
        // where the default may change.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            // Match the saved record's synchronizable flag so we never read
            // a stale iCloud-synced copy from a previous install era.
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    static func delete(key: String) -> Bool {
        // `kSecAttrSynchronizableAny` ensures the delete sweeps any old
        // iCloud-synced records left over from pre-hardening builds.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    // MARK: - String convenience

    static func saveString(_ string: String, for key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.saveFailed(errSecParam)
        }
        try save(data, for: key)
    }

    static func loadString(key: String) -> String? {
        guard let data = load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
