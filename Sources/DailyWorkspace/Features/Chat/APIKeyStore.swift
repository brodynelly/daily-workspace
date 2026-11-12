import Foundation
import Security

/// Storage for the OpenRouter API key.
protocol APIKeyStore {
    func read() throws -> String?
    /// Store `key`; an empty key deletes it.
    func save(_ key: String) throws
}

/// The key lives only in the login Keychain: never in UserDefaults, the vault, or chat history.
struct KeychainAPIKeyStore: APIKeyStore {
    var service = "app.dailyworkspace.openrouter"
    var account = "api-key"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw keychainError(status) }
        return String(data: data, encoding: .utf8)
    }

    func save(_ key: String) throws {
        if key.isEmpty {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status) }
            return
        }
        let update = SecItemUpdate(
            baseQuery as CFDictionary, [kSecValueData as String: Data(key.utf8)] as CFDictionary)
        if update == errSecItemNotFound {
            var entry = baseQuery
            entry[kSecValueData as String] = Data(key.utf8)
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let status = SecItemAdd(entry as CFDictionary, nil)
            guard status == errSecSuccess else { throw keychainError(status) }
        } else if update != errSecSuccess {
            throw keychainError(update)
        }
    }

    private func keychainError(_ status: OSStatus) -> NSError {
        let text = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain access failed."
        return NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: text])
    }
}
