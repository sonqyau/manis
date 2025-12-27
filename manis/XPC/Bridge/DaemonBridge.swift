import Foundation
import OSLog
import XPC

final class DaemonBridge: @unchecked Sendable {
    private let serviceName = "com.manis.Daemon"
    private var session: XPCSession?
    private let logger = Logger(subsystem: "com.manis.XPC", category: "DaemonBridge")

    private func getOrCreateSession() throws -> XPCSession {
        if let session {
            return session
        }

        let newSession = try XPCSession(
            machService: serviceName,
            targetQueue: nil,
            options: [],
        ) { [weak self] _ in
            self?.session = nil
            self?.logger.info("Daemon session cancelled")
        }

        try newSession.activate()
        self.session = newSession

        logger.info("Created new daemon session")
        return newSession
    }

    private func sendRequest(_ request: DaemonRequest) async throws -> DaemonResponse {
        let session = try getOrCreateSession()

        logger.debug("Sending request to daemon: \(request.method)")

        let response: DaemonResponse = try session.sendSync(request)

        logger.debug("Received response from daemon: \(request.method)")

        if case let .error(error) = response {
            throw error
        }

        return response
    }

    func getMihomoStatus() async throws -> MihomoStatus {
        let request = DaemonRequest(method: "getMihomoStatus")
        let response = try await sendRequest(request)

        guard case let .mihomoStatus(status) = response else {
            throw MainXPCError(domain: "com.manis.XPC", code: -1, message: "Unexpected response type")
        }

        return status
    }

    func startMihomo(executablePath: String, configPath: String, configContent: String) async throws -> String {
        let request = DaemonRequest(
            method: "startMihomo",
            executablePath: XPCConfigPath(executablePath),
            configPath: XPCConfigPath(configPath),
            configContent: configContent,
        )
        let response = try await sendRequest(request)

        guard case let .message(message) = response else {
            throw MainXPCError(domain: "com.manis.XPC", code: -1, message: "Unexpected response type")
        }

        return message
    }

    func stopMihomo() async throws {
        let request = DaemonRequest(method: "stopMihomo")
        let response = try await sendRequest(request)

        guard case .message = response else {
            throw MainXPCError(domain: "com.manis.XPC", code: -1, message: "Unexpected response type")
        }
    }

    func restartMihomo() async throws -> String {
        let request = DaemonRequest(method: "restartMihomo")
        let response = try await sendRequest(request)

        guard case let .message(message) = response else {
            throw MainXPCError(domain: "com.manis.XPC", code: -1, message: "Unexpected response type")
        }

        return message
    }

    func enableConnect(httpPort: Int, socksPort: Int, pacURL: String?, bypassList: [String]) async throws {
        let request = DaemonRequest(
            method: "enableConnect",
            httpPort: XPCPort(httpPort),
            socksPort: XPCPort(socksPort),
            pacURL: pacURL,
            bypassList: bypassList,
        )
        let response = try await sendRequest(request)

        guard case .message = response else {
            throw MainXPCError(domain: "com.manis.XPC", code: -1, message: "Unexpected response type")
        }
    }

    func disableConnect() async throws {
        let request = DaemonRequest(method: "disableConnect")
        let response = try await sendRequest(request)

        guard case .message = response else {
            throw MainXPCError(domain: "com.manis.XPC", code: -1, message: "Unexpected response type")
        }
    }

    func getConnectStatus() async throws -> ConnectStatus {
        let request = DaemonRequest(method: "getConnectStatus")
        let response = try await sendRequest(request)

        guard case let .systemProxyStatus(status) = response else {
            throw MainXPCError(domain: "com.manis.XPC", code: -1, message: "Unexpected response type")
        }

        return status
    }

    func configureDNS(servers: [String], hijackEnabled: Bool) async throws {
        let request = DaemonRequest(
            method: "configureDNS",
            servers: servers,
            hijackEnabled: hijackEnabled,
        )
        let response = try await sendRequest(request)

        guard case .message = response else {
            throw MainXPCError(domain: "com.manis.XPC", code: -1, message: "Unexpected response type")
        }
    }

    func flushDNSCache() async throws {
        let request = DaemonRequest(method: "flushDNSCache")
        let response = try await sendRequest(request)

        guard case .message = response else {
            throw MainXPCError(domain: "com.manis.XPC", code: -1, message: "Unexpected response type")
        }
    }

    func getUsedPorts() async throws -> [Int] {
        let request = DaemonRequest(method: "getUsedPorts")
        let response = try await sendRequest(request)

        guard case let .usedPorts(ports) = response else {
            throw MainXPCError(domain: "com.manis.XPC", code: -1, message: "Unexpected response type")
        }

        return ports
    }

    func testConnectivity(host: String, port: Int, timeout: TimeInterval) async throws -> Bool {
        let request = DaemonRequest(
            method: "testConnectivity",
            host: host,
            port: XPCPort(port),
            timeout: timeout,
        )
        let response = try await sendRequest(request)

        guard case let .connectivity(result) = response else {
            throw MainXPCError(domain: "com.manis.XPC", code: -1, message: "Unexpected response type")
        }

        return result
    }

    func updateTun(enabled: Bool, dnsServer: String) async throws {
        let request = DaemonRequest(
            method: "updateTun",
            enabled: enabled,
            dnsServer: dnsServer,
        )
        let response = try await sendRequest(request)

        guard case .message = response else {
            throw MainXPCError(domain: "com.manis.XPC", code: -1, message: "Unexpected response type")
        }
    }
}
