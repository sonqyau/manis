import Dependencies
import Foundation
import OSLog
import SwiftData

private struct PersistenceModelDependencies {
    @Dependency(\.uuid)
    var uuid

    @Dependency(\.date)
    var date
}

private enum RemoteInstanceKeychain {
    static let prefix = "com.manis.remote-instance"

    static func key(for id: UUID) -> String {
        "\(prefix).\(id.uuidString)"
    }
}

private struct RemoteInstanceDependencies {
    @Dependency(\.keychain)
    var keychain
}

@Model
final class PersistenceModel: Identifiable {
    @Attribute(.unique)
    var id: UUID

    var name: String
    var url: String
    var lastUpdated: Date?
    var isActive: Bool
    var autoUpdate: Bool

    @Attribute var createdAt: Date

    @Attribute var updatedAt: Date

    init(name: String, url: String, autoUpdate: Bool = true) {
        let dependencies = PersistenceModelDependencies()
        id = dependencies.uuid()
        self.name = name
        self.url = url
        self.autoUpdate = autoUpdate
        isActive = false
        lastUpdated = nil
        createdAt = dependencies.date()
        updatedAt = dependencies.date()
    }

    func displayTimeString() -> String {
        guard let date = lastUpdated else {
            return String(localized: "Never updated", table: "Localizable", bundle: .module)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

@Model
final class RemoteInstance: Identifiable {
    private static let logger = MainLog.shared.logger(for: .service)

    @Attribute(.unique)
    var id: UUID
    var name: String
    var apiURL: String
    var isActive: Bool

    var createdAt: Date
    var lastConnected: Date?

    init(name: String, apiURL: String, secret: String? = nil) {
        let dependencies = PersistenceModelDependencies()
        id = dependencies.uuid()
        self.name = name
        self.apiURL = apiURL
        isActive = false
        createdAt = dependencies.date()
        
        if let secret = secret, !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let keychainDeps = RemoteInstanceDependencies()
                try keychainDeps.keychain.setSecret(
                    secret,
                    RemoteInstanceKeychain.key(for: self.id)
                )
            } catch {
                Self.logger.error(
                    "Failed to store secret in Keychain during initialization",
                    metadata: ["error": String(describing: error)]
                )
            }
        }
    }

    @Transient var secret: String? {
        do {
            let dependencies = RemoteInstanceDependencies()
            return try dependencies.keychain.secret(
                RemoteInstanceKeychain.key(for: id)
            )
        } catch {
            Self.logger.error(
                "Unable to read secret from Keychain",
                metadata: ["error": String(describing: error)]
            )
            return nil
        }
    }

    func updateSecret(_ newSecret: String?) throws {
        let dependencies = RemoteInstanceDependencies()
        if let secret = newSecret, !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try dependencies.keychain.setSecret(
                secret,
                RemoteInstanceKeychain.key(for: id)
            )
        } else {
            try dependencies.keychain.deleteSecret(
                RemoteInstanceKeychain.key(for: id)
            )
        }
    }

    func clearSecret() throws {
        try updateSecret(nil)
    }
}
