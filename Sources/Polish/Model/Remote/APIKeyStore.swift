import Foundation
import Security

/// The API key, and only the API key, in the Keychain.
///
/// Filed per endpoint host: pointing Polish at a different provider must not silently send the old
/// provider's key to the new one. Nothing here ever returns the key inside an error, and no call
/// site logs the value.
enum APIKeyStore {
    static let service = "com.saswat.polish.apikey"

    enum StoreError: Error, Equatable {
        /// The Keychain refused, with its own status code. The code is safe to show; the key is not.
        case keychain(OSStatus)
    }

    private static func query(forHost host: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host,
        ]
    }

    /// Replaces any key already stored for `host`.
    static func save(_ key: String, forHost host: String) throws {
        try delete(forHost: host)
        guard !key.isEmpty else { return }

        var attributes = query(forHost: host)
        attributes[kSecValueData as String] = Data(key.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
    }

    /// `nil` for "no key stored" and for any Keychain failure alike: every caller's next move is
    /// the same — tell the user the endpoint is not configured.
    static func load(forHost host: String) -> String? {
        var attributes = query(forHost: host)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Deleting a key that is not there succeeds — `save` relies on that to overwrite.
    static func delete(forHost host: String) throws {
        let status = SecItemDelete(query(forHost: host) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychain(status)
        }
    }
}
