import Foundation
import OSLog

final class XPCService: @unchecked Sendable {
    private let daemonBridge: DaemonBridge
    private let logger = Logger(subsystem: "com.manis.XPC", category: "XPCService")

    init() {
        self.daemonBridge = DaemonBridge()
        logger.info("XPC Service initialized")
    }

    func getVersion() async throws -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        return version
    }

    func getKernelStatus() async throws -> ManisKernelStatus {
        let status = try await daemonBridge.getMihomoStatus()
        let kernelStatus = ManisKernelStatus(
            isRunning: status.isRunning,
            processId: status.processId,
            externalController: status.externalController,
            secret: status.secret,
            )
        return kernelStatus
    }

    func startKernel(_ request: KernelStartRequest) async throws -> String {
        let result = try await daemonBridge.startMihomo(
            executablePath: request.executablePath.rawValue,
            configPath: request.configPath.rawValue,
            configContent: request.configContent,
            )

        return result
    }

    func stopKernel() async throws -> String {
        try await daemonBridge.stopMihomo()
        return "Kernel terminated successfully"
    }

    func restartKernel() async throws -> String {
        let result = try await daemonBridge.restartMihomo()
        return result
    }

    func enableConnect(_ request: ConnectRequest) async throws -> String {
        try await daemonBridge.enableConnect(
            httpPort: request.httpPort.rawValue,
            socksPort: request.socksPort.rawValue,
            pacURL: request.pacURL,
            bypassList: request.bypassList,
            )

        return "System proxy activated successfully"
    }

    func disableConnect() async throws -> String {
        try await daemonBridge.disableConnect()
        return "System proxy deactivated successfully"
    }

    func getConnectStatus() async throws -> ConnectStatus {
        let status = try await daemonBridge.getConnectStatus()
        return status
    }

    func configureDNS(_ request: DNSRequest) async throws -> String {
        try await daemonBridge.configureDNS(servers: request.servers, hijackEnabled: request.hijackEnabled)
        return "DNS configuration updated successfully"
    }

    func flushDNSCache() async throws -> String {
        try await daemonBridge.flushDNSCache()
        return "DNS cache cleared successfully"
    }

    func getUsedPorts() async throws -> [Int] {
        let ports = try await daemonBridge.getUsedPorts()
        return ports
    }

    func testConnectivity(_ request: ConnectivityRequest) async throws -> Bool {
        let isConnected = try await daemonBridge.testConnectivity(
            host: request.host,
            port: request.port.rawValue,
            timeout: request.timeout,
            )

        return isConnected
    }

    func updateTun(_ request: TunRequest) async throws -> String {
        try await daemonBridge.updateTun(enabled: request.enabled, dnsServer: request.dnsServer)
        return "TUN configuration updated successfully"
    }
}
