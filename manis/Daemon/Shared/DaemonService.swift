import ConcurrencyExtras
import Foundation
import OSLog

actor DaemonService {
    private var state: DaemonState = .idle
    private let logger = Logger(subsystem: "com.manis.Daemon", category: "DaemonService")

    private let mihomoService: MihomoService
    private let connectService: ConnectService
    private let dnsService: DNSService
    private let networkService: NetworkService

    init() {
        self.mihomoService = MihomoService()
        self.connectService = MainDaemon.ConnectService()
        self.dnsService = DNSService()
        self.networkService = NetworkService()

        logger.info("DaemonService initialized")
    }

    private func transitionTo(_ newState: DaemonState) {
        let oldState = state
        state = newState
        logger.info("State transition: \(String(describing: oldState)) -> \(String(describing: newState))")
    }

    func handleRequest(_ request: DaemonRequest) async -> DaemonResponse {
        logger.debug("Handling request: \(request.method)")

        do {
            switch request.method {
            case "getVersion":
                return try await getVersion()

            case "getMihomoStatus":
                return try await getMihomoStatus()

            case "startMihomo":
                return try await startMihomo(request)

            case "stopMihomo":
                return try await stopMihomo()

            case "restartMihomo":
                return try await restartMihomo()

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
                throw DaemonError.serviceUnavailable("Unknown method: \(request.method)")
            }
        } catch {
            logger.error("Request failed: \(error.localizedDescription)")
            return .error(MainXPCError(error: error))
        }
    }

    private func getVersion() async throws -> DaemonResponse {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        return .version(version)
    }

    private func getMihomoStatus() async throws -> DaemonResponse {
        let status = await mihomoService.getStatus()
        return .mihomoStatus(status)
    }

    private func startMihomo(_ request: DaemonRequest) async throws -> DaemonResponse {
        guard let executablePath = request.executablePath,
              let configPath = request.configPath,
              let configContent = request.configContent
        else {
            throw DaemonError.configurationError("Missing required parameters for startMihomo")
        }

        let result = try await mihomoService.start(
            executablePath: executablePath,
            configPath: configPath,
            configContent: configContent,
            )

        return .message(result)
    }

    private func stopMihomo() async throws -> DaemonResponse {
        try await mihomoService.stop()
        return .message("Mihomo stopped successfully")
    }

    private func restartMihomo() async throws -> DaemonResponse {
        let result = try await mihomoService.restart()
        return .message(result)
    }

    private func enableConnect(_ request: DaemonRequest) async throws -> DaemonResponse {
        guard let httpPort = request.httpPort,
              let socksPort = request.socksPort
        else {
            throw DaemonError.configurationError("Missing required ports for enableConnect")
        }

        try await connectService.enable(
            httpPort: httpPort,
            socksPort: socksPort,
            pacURL: request.pacURL,
            bypassList: request.bypassList ?? [],
            )

        return .message("System proxy enabled successfully")
    }

    private func disableConnect() async throws -> DaemonResponse {
        try await connectService.disable()
        return .message("System proxy disabled successfully")
    }

    private func getConnectStatus() async throws -> DaemonResponse {
        let status = await connectService.getStatus()
        return .systemProxyStatus(status)
    }

    private func configureDNS(_ request: DaemonRequest) async throws -> DaemonResponse {
        guard let servers = request.servers else {
            throw DaemonError.configurationError("Missing required parameters for configureDNS")
        }

        try await dnsService.configure(servers: servers, hijackEnabled: request.hijackEnabled)
        return .message("DNS configured successfully")
    }

    private func flushDNSCache() async throws -> DaemonResponse {
        try await dnsService.flushCache()
        return .message("DNS cache flushed successfully")
    }

    private func getUsedPorts() async throws -> DaemonResponse {
        let ports = await networkService.getUsedPorts()
        return .usedPorts(ports)
    }

    private func testConnectivity(_ request: DaemonRequest) async throws -> DaemonResponse {
        guard let host = request.host,
              let port = request.port,
              let timeout = request.timeout
        else {
            throw DaemonError.configurationError("Missing required parameters for testConnectivity")
        }

        let isConnected = await networkService.testConnectivity(
            host: host,
            port: port,
            timeout: timeout,
            )

        return .connectivity(isConnected)
    }

    private func updateTun(_ request: DaemonRequest) async throws -> DaemonResponse {
        guard request.dnsServer != nil else {
            throw DaemonError.configurationError("Missing required parameters for updateTun")
        }

        // TODO: Implement TUN with enabled: request.enabled, dnsServer: dnsServer
        throw DaemonError.serviceUnavailable("TUN update not implemented yet")
    }
}
