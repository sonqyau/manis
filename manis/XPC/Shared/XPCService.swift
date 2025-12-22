import Foundation
import OSLog

final class XPCService: @unchecked Sendable {
    private let daemonBridge: DaemonBridge
    private let logger = Logger(subsystem: "com.manis.XPC", category: "XPCService")

    init() {
        self.daemonBridge = DaemonBridge()
        logger.info("XPC Service initialized")
    }

    func handleRequest(_ request: XPCRequest) async -> XPCResponse {
        logger.debug("Handling XPC request: \(request.method)")

        do {
            let response = try await processRequest(request)
            logger.debug("XPC request completed: \(request.method)")
            return response
        } catch {
            logger.error("XPC request failed: \(error.localizedDescription)")
            return .error(MainXPCError(error: error))
        }
    }

    private func processRequest(_ request: XPCRequest) async throws -> XPCResponse {
        switch request.method {
        case "getVersion":
            return try await getVersion()

        case "getKernelStatus":
            return try await getKernelStatus()

        case "startKernel":
            return try await startKernel(request)

        case "stopKernel":
            return try await stopKernel()

        case "restartKernel":
            return try await restartKernel()

        case "enableConnect":
            return try await enableConnect(request)

        case "disableConnect":
            return try await disableConnect()

        case "getConnectStatus":
            return try await getConnectStatus()

        case "configureDNS":
            return try await configureDNS(request)

        case "flushDNSCache":
            return try await flushDNSCache()

        case "getUsedPorts":
            return try await getUsedPorts()

        case "testConnectivity":
            return try await testConnectivity(request)

        case "updateTun":
            return try await updateTun(request)

        default:
            throw MainXPCError(domain: "com.manis.XPC", code: -1, message: "Unknown method: \(request.method)")
        }
    }

    private func getVersion() async throws -> XPCResponse {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        return .version(version)
    }

    private func getKernelStatus() async throws -> XPCResponse {
        let status = try await daemonBridge.getMihomoStatus()
        let kernelStatus = ManisKernelStatus(
            isRunning: status.isRunning,
            processId: status.processId,
            externalController: status.externalController,
            secret: status.secret,
        )
        return .kernelStatus(kernelStatus)
    }

    private func startKernel(_ request: XPCRequest) async throws -> XPCResponse {
        guard let executablePath = request.executablePath,
              let configPath = request.configPath,
              let configContent = request.configContent
        else {
            throw MainXPCError(domain: "com.manis.XPC", code: -2, message: "Missing required parameters")
        }

        let result = try await daemonBridge.startMihomo(
            executablePath: executablePath,
            configPath: configPath,
            configContent: configContent,
        )

        return .message(result)
    }

    private func stopKernel() async throws -> XPCResponse {
        try await daemonBridge.stopMihomo()
        return .message("Kernel stopped successfully")
    }

    private func restartKernel() async throws -> XPCResponse {
        let result = try await daemonBridge.restartMihomo()
        return .message(result)
    }

    private func enableConnect(_ request: XPCRequest) async throws -> XPCResponse {
        guard let httpPort = request.httpPort,
              let socksPort = request.socksPort
        else {
            throw MainXPCError(domain: "com.manis.XPC", code: -2, message: "Missing required ports")
        }

        try await daemonBridge.enableConnect(
            httpPort: httpPort,
            socksPort: socksPort,
            pacURL: request.pacURL,
            bypassList: request.bypassList ?? [],
        )

        return .message("System proxy enabled successfully")
    }

    private func disableConnect() async throws -> XPCResponse {
        try await daemonBridge.disableConnect()
        return .message("System proxy disabled successfully")
    }

    private func getConnectStatus() async throws -> XPCResponse {
        let status = try await daemonBridge.getConnectStatus()
        return .systemProxyStatus(status)
    }

    private func configureDNS(_ request: XPCRequest) async throws -> XPCResponse {
        guard let servers = request.servers else {
            throw MainXPCError(domain: "com.manis.XPC", code: -2, message: "Missing required DNS parameters")
        }

        try await daemonBridge.configureDNS(servers: servers, hijackEnabled: request.hijackEnabled)
        return .message("DNS configured successfully")
    }

    private func flushDNSCache() async throws -> XPCResponse {
        try await daemonBridge.flushDNSCache()
        return .message("DNS cache flushed successfully")
    }

    private func getUsedPorts() async throws -> XPCResponse {
        let ports = try await daemonBridge.getUsedPorts()
        return .usedPorts(ports)
    }

    private func testConnectivity(_ request: XPCRequest) async throws -> XPCResponse {
        guard let host = request.host,
              let port = request.port,
              let timeout = request.timeout
        else {
            throw MainXPCError(domain: "com.manis.XPC", code: -2, message: "Missing connectivity test parameters")
        }

        let isConnected = try await daemonBridge.testConnectivity(
            host: host,
            port: port,
            timeout: timeout,
        )

        return .connectivity(isConnected)
    }

    private func updateTun(_ request: XPCRequest) async throws -> XPCResponse {
        guard let dnsServer = request.dnsServer else {
            throw MainXPCError(domain: "com.manis.XPC", code: -2, message: "Missing TUN parameters")
        }

        try await daemonBridge.updateTun(enabled: request.enabled, dnsServer: dnsServer)
        return .message("TUN updated successfully")
    }
}
