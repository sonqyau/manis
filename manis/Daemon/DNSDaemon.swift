import Foundation
import OSLog
import SystemConfiguration

class DNSDaemon {
    private let logger = Logger(subsystem: "com.manis.Daemon", category: "DNSDaemon")
    private var originalDNSSettings: [String: [String: Any]] = [:]

    func configure(
        servers: [String],
        hijackEnabled: Bool,
        completion: @escaping (Result<Void, Error>) -> Void,
        ) {
        do {
            if hijackEnabled {
                try hijackDNS(servers: servers)
            } else {
                try restoreDNS()
            }

            flushCache { _ in }

            logger.info("DNS configured successfully")
            completion(.success(()))
        } catch {
            logger.error("Failed to configure DNS: \(error)")
            completion(.failure(error))
        }
    }

    func flushCache(completion: @escaping (Result<Void, Error>) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
        process.arguments = ["-flushcache"]

        do {
            try process.run()
            process.waitUntilExit()

            let mdnsProcess = Process()
            mdnsProcess.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            mdnsProcess.arguments = ["-HUP", "mDNSResponder"]

            try mdnsProcess.run()
            mdnsProcess.waitUntilExit()

            logger.info("DNS cache flushed successfully")
            completion(.success(()))
        } catch {
            logger.error("Failed to flush DNS cache: \(error)")
            completion(.failure(error))
        }
    }

    private func hijackDNS(servers: [String]) throws {
        let dynamicStore = SCDynamicStoreCreate(nil, "com.manis.Daemon" as CFString, nil, nil)
        guard let store = dynamicStore else {
            throw DNSError.storeCreationFailed
        }

        let services = getNetworkServices()

        for service in services {
            let dnsKey = "State:/Network/Service/\(service)/DNS" as CFString

            if let originalSettings = SCDynamicStoreCopyValue(store, dnsKey) as? [String: Any] {
                originalDNSSettings[service] = originalSettings
            }

            let dnsDict: [String: Any] = [
                "ServerAddresses": servers,
            ]

            if !SCDynamicStoreSetValue(store, dnsKey, dnsDict as CFDictionary) {
                throw DNSError.settingsFailed
            }
        }
    }

    private func restoreDNS() throws {
        let dynamicStore = SCDynamicStoreCreate(nil, "com.manis.Daemon" as CFString, nil, nil)
        guard let store = dynamicStore else {
            throw DNSError.storeCreationFailed
        }

        for (service, originalSettings) in originalDNSSettings {
            let dnsKey = "State:/Network/Service/\(service)/DNS" as CFString

            if !SCDynamicStoreSetValue(store, dnsKey, originalSettings as CFDictionary) {
                throw DNSError.settingsFailed
            }
        }

        originalDNSSettings.removeAll()
    }

    private func getNetworkServices() -> [String] {
        let dynamicStore = SCDynamicStoreCreate(nil, "com.manis.Daemon" as CFString, nil, nil)
        guard let store = dynamicStore else { return [] }

        let pattern = "State:/Network/Service/[^/]+/IPv4" as CFString
        guard let keys = SCDynamicStoreCopyKeyList(store, pattern) as? [String] else {
            return []
        }

        return keys.compactMap { key in
            let components = key.components(separatedBy: "/")
            return components.count >= 4 ? components[3] : nil
        }
    }
}

enum DNSError: Error, LocalizedError {
    case storeCreationFailed
    case settingsFailed

    var errorDescription: String? {
        switch self {
        case .storeCreationFailed:
            "Failed to create system configuration store"
        case .settingsFailed:
            "Failed to apply DNS settings"
        }
    }
}
