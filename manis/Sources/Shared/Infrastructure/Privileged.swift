import Foundation
import OSLog
import ServiceManagement

@objc public protocol ProtocolProxyDaemon {
    func getVersion(reply: @escaping @Sendable (String) -> Void)
    func enableProxy(
        port: Int,
        socksPort: Int,
        pac: String?,
        filterInterface: Bool,
        ignoreList: [String],
        reply: @escaping @Sendable ((any Error)?) -> Void,
    )
    func disableProxy(filterInterface: Bool, reply: @escaping @Sendable ((any Error)?) -> Void)
    func restoreProxy(
        currentPort: Int,
        socksPort: Int,
        info: [String: Any],
        filterInterface: Bool,
        reply: @escaping @Sendable ((any Error)?) -> Void,
    )
    func getCurrentProxySetting(reply: @escaping @Sendable ([String: Any]) -> Void)
    func startMihomo(
        path: String,
        confPath: String,
        confFilePath: String,
        confJSON: String,
        reply: @escaping @Sendable ((any Error)?) -> Void,
    )
    func stopMihomo(reply: @escaping @Sendable ((any Error)?) -> Void)
    func getUsedPorts(reply: @escaping @Sendable (String?) -> Void)
    func updateTun(state: Bool, dns: String, reply: @escaping @Sendable ((any Error)?) -> Void)
    func flushDnsCache(reply: @escaping @Sendable ((any Error)?) -> Void)
    func enableTUNMode(dnsServer: String, reply: @escaping @Sendable ((any Error)?) -> Void)
    func disableTUNMode(reply: @escaping @Sendable ((any Error)?) -> Void)
    func getTUNStatus(reply: @escaping @Sendable ([String: Any]) -> Void)
    func validateKernelBinary(path: String, reply: @escaping @Sendable ((any Error)?) -> Void)
}

enum HelperToolError: Error, LocalizedError {
    case installationFailed(String)
    case authorizationFailed
    case helperNotFound
    case communicationFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case let .installationFailed(reason):
            "Helper tool installation failed: \(reason)"
        case .authorizationFailed:
            "Authorization failed. Administrator privileges required."
        case .helperNotFound:
            "Helper tool not found or not running."
        case .communicationFailed:
            "Failed to communicate with helper tool."
        case .invalidResponse:
            "Invalid response from helper tool."
        }
    }
}

@MainActor
final class Privileged: ObservableObject {
    static let shared = Privileged()

    private let logger = Logger(subsystem: "com.sonqyau.manis", category: "helper")
    private let helperIdentifier = "com.sonqyau.manis.daemon"

    @Published var isInstalled = false
    @Published var isRunning = false

    private var connection: NSXPCConnection?

    private init() {
        checkHelperStatus()
    }

    func checkHelperStatus() {
        Task {
            await updateHelperStatus()
        }
    }

    private func updateHelperStatus() async {
        let service = SMAppService.daemon(plistName: helperIdentifier)
        let status = service.status

        switch status {
        case .enabled:
            isInstalled = true
            isRunning = await checkHelperRunning()
        case .requiresApproval:
            isInstalled = true
            isRunning = false
        case .notRegistered, .notFound:
            isInstalled = false
            isRunning = false
        @unknown default:
            isInstalled = false
            isRunning = false
        }

        let statusDescription = switch status {
        case .enabled: "enabled"
        case .requiresApproval: "requiresApproval"
        case .notRegistered: "notRegistered"
        case .notFound: "notFound"
        @unknown default: "unknown"
        }
        logger.info("Helper status - Installed: \(self.isInstalled), Running: \(self.isRunning), SMAppService Status: \(statusDescription)")
    }

    private func checkHelperRunning() async -> Bool {
        do {
            let connection = try await getConnection()
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                self.logger.error("Helper connection error: \(error.localizedDescription)")
            } as? ProtocolProxyDaemon

            return await withCheckedContinuation { continuation in
                proxy?.getVersion { version in
                    continuation.resume(returning: !version.isEmpty)
                }
            }
        } catch {
            return false
        }
    }

    func installHelper() async throws {
        logger.info("Installing helper tool using SMAppService")

        do {
            try SMAppService.daemon(plistName: helperIdentifier).register()
            await updateHelperStatus()
            logger.info("Helper tool registered successfully via SMAppService")
        } catch {
            logger.error("Helper registration failed: \(error.localizedDescription)")
            throw HelperToolError.installationFailed(error.localizedDescription)
        }
    }

    func uninstallHelper() async throws {
        logger.info("Uninstalling helper tool using SMAppService")

        do {
            try await SMAppService.daemon(plistName: helperIdentifier).unregister()

            connection?.invalidate()
            connection = nil

            await updateHelperStatus()
            logger.info("Helper tool unregistered successfully via SMAppService")
        } catch {
            logger.error("Helper unregistration failed: \(error.localizedDescription)")
            throw HelperToolError.installationFailed(error.localizedDescription)
        }
    }

    func getConnection() async throws -> NSXPCConnection {
        if let existingConnection = connection {
            return existingConnection
        }

        let newConnection = NSXPCConnection(machServiceName: helperIdentifier, options: .privileged)
        newConnection.remoteObjectInterface = NSXPCInterface(with: ProtocolProxyDaemon.self)

        newConnection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.isRunning = false
                self?.logger.debug("Helper connection invalidated")
            }
        }

        newConnection.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.logger.warning("Helper connection interrupted")
            }
        }

        newConnection.resume()
        connection = newConnection

        let proxy = newConnection.remoteObjectProxyWithErrorHandler { error in
            self.logger.error("Helper proxy error: \(error.localizedDescription)")
        } as? ProtocolProxyDaemon

        let isConnected = await withCheckedContinuation { continuation in
            proxy?.getVersion { version in
                continuation.resume(returning: !version.isEmpty)
            }
        }

        if !isConnected {
            newConnection.invalidate()
            connection = nil
            throw HelperToolError.communicationFailed
        }

        isRunning = true
        return newConnection
    }

    func getHelperProxy() async throws -> ProtocolProxyDaemon {
        let connection = try await getConnection()

        guard let proxy = connection.remoteObjectProxy as? ProtocolProxyDaemon else {
            throw HelperToolError.invalidResponse
        }

        return proxy
    }
}
