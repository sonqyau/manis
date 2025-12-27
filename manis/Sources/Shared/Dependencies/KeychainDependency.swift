import Dependencies

struct KeychainClient {
    var setSecret: @Sendable (_ secret: String, _ key: String) throws -> Void
    var secret: @Sendable (_ key: String) throws -> String?
    var deleteSecret: @Sendable (_ key: String) throws -> Void
    var containsSecret: @Sendable (_ key: String) throws -> Bool
    var removeAllSecrets: @Sendable () throws -> Void
    var allKeys: @Sendable () throws -> Set<String>
    var canAccessKeychain: @Sendable () -> Bool
}

enum KeychainClientKey: DependencyKey {
    static let liveValue = KeychainClient(
        setSecret: { secret, key in
            try Keychain.shared.setSecret(secret, for: key)
        },
        secret: { key in
            try Keychain.shared.secret(for: key)
        },
        deleteSecret: { key in
            try Keychain.shared.deleteSecret(for: key)
        },
        containsSecret: { key in
            try Keychain.shared.containsSecret(for: key)
        },
        removeAllSecrets: {
            try Keychain.shared.removeAllSecrets()
        },
        allKeys: {
            try Keychain.shared.allKeys()
        },
        canAccessKeychain: {
            Keychain.shared.canAccessKeychain()
        },
    )
}

extension DependencyValues {
    var keychain: KeychainClient {
        get { self[KeychainClientKey.self] }
        set { self[KeychainClientKey.self] = newValue }
    }
}

struct KeychainDependency {}
