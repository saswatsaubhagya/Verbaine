import Foundation
import Security

/// The API key, and only the API key, in the Keychain.
///
/// Filed per endpoint host: pointing Verbaine at a different provider must not silently send the old
/// provider's key to the new one. Nothing here ever returns the key inside an error, and no call
/// site logs the value.
enum APIKeyStore {
    static let service = "in.saswatsaubhagya.verbaine.apikey"

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

    /// Replaces any key already stored for `host` — but never by deleting first. Deleting before
    /// adding would leave the host with no key at all if the add then failed, silently destroying
    /// a key that previously worked. Instead this adds fresh, and only updates the existing item
    /// in place once the Keychain reports one is already there.
    static func save(_ key: String, forHost host: String) throws {
        guard !key.isEmpty else {
            try delete(forHost: host)
            return
        }

        let base = query(forHost: host)
        var addAttributes = base
        addAttributes[kSecValueData as String] = Data(key.utf8)
        addAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(addAttributes as CFDictionary, nil)
        if addStatus == errSecSuccess { return }
        guard addStatus == errSecDuplicateItem else { throw StoreError.keychain(addStatus) }

        let updateStatus = SecItemUpdate(base as CFDictionary, [kSecValueData as String: Data(key.utf8)] as CFDictionary)
        guard updateStatus == errSecSuccess else { throw StoreError.keychain(updateStatus) }
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

    /// Deleting a key that is not there succeeds — `save` relies on that for the empty-key
    /// ("clear this host's key") case; overwriting an existing key no longer goes through delete.
    static func delete(forHost host: String) throws {
        let status = SecItemDelete(query(forHost: host) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychain(status)
        }
    }
}
