import Foundation
import OSLog

actor ConnectService {
    private var state: ConnectState = .disabled
    private let logger = Logger(subsystem: "com.manis.Daemon", category: "ConnectService")

    func enable(httpPort: Int, socksPort: Int, pacURL: String?, bypassList: [String]) async throws {
        guard case .disabled = state else {
            throw DaemonError.invalidStateTransition(
                from: String(describing: state),
                to: "enabling",
                )
        }

        state = .enabling
        logger.info("Enabling system proxy - HTTP: \(httpPort), SOCKS: \(socksPort)")

        do {
            let config = ProxyConfiguration(
                httpPort: httpPort,
                socksPort: socksPort,
                pacURL: pacURL,
                bypassList: bypassList,
                )

            try await enableConnect(config: config)
            state = .enabled(config)
            logger.info("System proxy enabled successfully")
        } catch {
            state = .error(error)
            logger.error("Failed to enable system proxy: \(error.localizedDescription)")
            throw error
        }
    }

    func disable() async throws {
        guard case .enabled = state else {
            logger.info("System proxy already disabled")
            return
        }

        state = .disabling
        logger.info("Disabling system proxy")

        do {
            try await disableConnect()
            state = .disabled
            logger.info("System proxy disabled successfully")
        } catch {
            state = .error(error)
            logger.error("Failed to disable system proxy: \(error.localizedDescription)")
            throw error
        }
    }

    func getStatus() async -> ConnectStatus {
        switch state {
        case .disabled:
            ConnectStatus(
                isEnabled: false,
                httpProxy: nil,
                httpsProxy: nil,
                socksProxy: nil,
                pacURL: nil,
                bypassList: [],
                )

        case .enabling, .disabling:
            ConnectStatus(
                isEnabled: false,
                httpProxy: nil,
                httpsProxy: nil,
                socksProxy: nil,
                pacURL: nil,
                bypassList: [],
                )

        case let .enabled(config):
            ConnectStatus(
                isEnabled: true,
                httpProxy: ConnectInfo(host: "127.0.0.1", port: Int32(config.httpPort)),
                httpsProxy: ConnectInfo(host: "127.0.0.1", port: Int32(config.httpPort)),
                socksProxy: ConnectInfo(host: "127.0.0.1", port: Int32(config.socksPort)),
                pacURL: config.pacURL,
                bypassList: config.bypassList,
                )

        case .error:
            ConnectStatus(
                isEnabled: false,
                httpProxy: nil,
                httpsProxy: nil,
                socksProxy: nil,
                pacURL: nil,
                bypassList: [],
                )
        }
    }

    private func enableConnect(config: ProxyConfiguration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.setHTTPProxy(host: "127.0.0.1", port: config.httpPort)

                    try self.setHTTPSProxy(host: "127.0.0.1", port: config.httpPort)

                    try self.setSOCKSProxy(host: "127.0.0.1", port: config.socksPort)

                    if let pacURL = config.pacURL {
                        try self.setPACURL(pacURL)
                    }

                    if !config.bypassList.isEmpty {
                        try self.setBypassList(config.bypassList)
                    }

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func disableConnect() async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.disableHTTPProxy()
                    try self.disableHTTPSProxy()
                    try self.disableSOCKSProxy()
                    try self.disablePAC()

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private func setHTTPProxy(host: String, port: Int) throws {
        let result = executeNetworkSetup([
            "-setwebproxy", "Wi-Fi", host, "\(port)",
        ])

        if result != 0 {
            throw DaemonError.networkError("Failed to set HTTP proxy")
        }
    }

    nonisolated private func setHTTPSProxy(host: String, port: Int) throws {
        let result = executeNetworkSetup([
            "-setsecurewebproxy", "Wi-Fi", host, "\(port)",
        ])

        if result != 0 {
            throw DaemonError.networkError("Failed to set HTTPS proxy")
        }
    }

    nonisolated private func setSOCKSProxy(host: String, port: Int) throws {
        let result = executeNetworkSetup([
            "-setsocksfirewallproxy", "Wi-Fi", host, "\(port)",
        ])

        if result != 0 {
            throw DaemonError.networkError("Failed to set SOCKS proxy")
        }
    }

    nonisolated private func setPACURL(_ url: String) throws {
        let result = executeNetworkSetup([
            "-setautoproxyurl", "Wi-Fi", url,
        ])

        if result != 0 {
            throw DaemonError.networkError("Failed to set PAC URL")
        }
    }

    nonisolated private func setBypassList(_ bypassList: [String]) throws {
        let bypassString = bypassList.joined(separator: " ")
        let result = executeNetworkSetup([
            "-setproxybypassdomains", "Wi-Fi", bypassString,
        ])

        if result != 0 {
            throw DaemonError.networkError("Failed to set bypass list")
        }
    }

    nonisolated private func disableHTTPProxy() throws {
        let result = executeNetworkSetup([
            "-setwebproxystate", "Wi-Fi", "off",
        ])

        if result != 0 {
            throw DaemonError.networkError("Failed to disable HTTP proxy")
        }
    }

    nonisolated private func disableHTTPSProxy() throws {
        let result = executeNetworkSetup([
            "-setsecurewebproxystate", "Wi-Fi", "off",
        ])

        if result != 0 {
            throw DaemonError.networkError("Failed to disable HTTPS proxy")
        }
    }

    nonisolated private func disableSOCKSProxy() throws {
        let result = executeNetworkSetup([
            "-setsocksfirewallproxystate", "Wi-Fi", "off",
        ])

        if result != 0 {
            throw DaemonError.networkError("Failed to disable SOCKS proxy")
        }
    }

    nonisolated private func disablePAC() throws {
        let result = executeNetworkSetup([
            "-setautoproxystate", "Wi-Fi", "off",
        ])

        if result != 0 {
            throw DaemonError.networkError("Failed to disable PAC")
        }
    }

    nonisolated private func executeNetworkSetup(_ arguments: [String]) -> Int32 {
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
