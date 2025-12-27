import Foundation
import OSLog

actor DNSService {
    private var state: DNSState = .default
    private let logger = Logger(subsystem: "com.manis.Daemon", category: "DNSService")

    func configure(servers: [String], hijackEnabled: Bool) async throws {
        state = .configuring
        logger.info("Configuring DNS - servers: \(servers), hijack: \(hijackEnabled)")

        do {
            let config = DNSConfiguration(servers: servers, hijackEnabled: hijackEnabled)
            try await configureDNSServers(config: config)
            state = .configured(config)
            logger.info("DNS configured successfully")
        } catch {
            state = .error(error)
            logger.error("Failed to configure DNS: \(error.localizedDescription)")
            throw error
        }
    }

    func flushCache() async throws {
        logger.info("Flushing DNS cache")

        do {
            try await flushDNSCache()
            logger.info("DNS cache flushed successfully")
        } catch {
            logger.error("Failed to flush DNS cache: \(error.localizedDescription)")
            throw error
        }
    }

    private func configureDNSServers(config: DNSConfiguration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.setDNSServers(config.servers)

                    if config.hijackEnabled {
                        try self.enableDNSHijacking()
                    } else {
                        try self.disableDNSHijacking()
                    }

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func flushDNSCache() async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.executeDNSFlush()

                if result == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DaemonError.networkError("Failed to flush DNS cache"))
                }
            }
        }
    }

    private nonisolated func setDNSServers(_ servers: [String]) throws {
        _ = servers.joined(separator: " ")
        let result = executeNetworkSetup([
            "-setdnsservers", "Wi-Fi",
        ] + servers)

        if result != 0 {
            throw DaemonError.networkError("Failed to set DNS servers")
        }
    }

    private nonisolated func enableDNSHijacking() throws {
        // DNS hijacking implementation not yet available
        logger.info("DNS hijacking enabled (placeholder)")
    }

    private nonisolated func disableDNSHijacking() throws {
        // DNS hijacking implementation not yet available
        logger.info("DNS hijacking disabled (placeholder)")
    }

    private nonisolated func executeDNSFlush() -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
        process.arguments = ["-flushcache"]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            logger.error("Failed to execute dscacheutil: \(error)")
            return -1
        }
    }

    private nonisolated func executeNetworkSetup(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            logger.error("Failed to execute networksetup: \(error)")
            return -1
        }
    }
}
