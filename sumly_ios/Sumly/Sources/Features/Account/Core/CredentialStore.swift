import Foundation
import Security

@MainActor protocol CredentialStoring {
    func load() throws -> StoredSession?
    func save(_ session: StoredSession) throws
    func clear() throws
}

/// The OS boundary is injectable so failure/relaunch tests never use a real Keychain account.
@MainActor protocol KeychainDataStoring {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func remove() throws
}
@MainActor final class KeychainCredentialStore: CredentialStoring {
    private let defaults: UserDefaults
    private let keychain: any KeychainDataStoring
    // Only a non-secret logout tombstone lives in defaults, never tokens or user data.
    private let logoutMarker = "native-auth-local-logout"

    init(defaults: UserDefaults = .standard, keychain: any KeychainDataStoring = SystemKeychainDataStore()) {
        self.defaults = defaults
        self.keychain = keychain
    }
    func load() throws -> StoredSession? {
        if defaults.bool(forKey: logoutMarker) {
            try clear()
            return nil
        }
        guard let data = try keychain.read() else { return nil }
        return try JSONDecoder().decode(StoredSession.self, from: data)
    }
    func save(_ session: StoredSession) throws {
        try keychain.write(JSONEncoder().encode(session))
        defaults.removeObject(forKey: logoutMarker)
    }
    func clear() throws {
        // If Keychain is temporarily locked, never restore the old session on relaunch.
        defaults.set(true, forKey: logoutMarker)
        try keychain.remove()
    }
}
@MainActor final class SystemKeychainDataStore: KeychainDataStoring {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.oryjk.sumly.native-auth", kSecAttrAccount as String: "session-v1"]
    }
    func read() throws -> Data? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw AuthError.keychain(status) }
        return data
    }
    func write(_ data: Data) throws {
        let attributes: [String: Any] = [kSecValueData as String: data,
                                       kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let insert = query.merging(attributes) { _, new in new }
            let inserted = SecItemAdd(insert as CFDictionary, nil)
            guard inserted == errSecSuccess else { throw AuthError.keychain(inserted) }
        } else if status != errSecSuccess { throw AuthError.keychain(status) }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AuthError.keychain(status) }
    }
}
