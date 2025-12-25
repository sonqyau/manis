import Foundation
import OSLog
import ServiceManagement

@MainActor
final class DaemonManager {
    static let shared = DaemonManager()

    let helperPlistName = "com.manis.Daemon"
    let logger = Logger(subsystem: "com.manis.app", category: "DaemonManager")

    private init() {}

    private var service: SMAppService {
        SMAppService.daemon(plistName: helperPlistName)
    }

    var status: SMAppService.Status {
        service.status
    }

    func checkAndHandleApprovalStatus() -> Bool {
        let currentStatus = service.status
        logger.info("Daemon status: \(String(describing: currentStatus))")

        switch currentStatus {
        case .requiresApproval:
            logger.warning("Daemon requires user approval in System Settings")
            openSystemSettingsForApproval()
            return false
        case .notRegistered:
            logger.info("Daemon not registered, attempting registration")
            do {
                try register()
                return service.status == .enabled
            } catch {
                logger.error("Failed to register daemon: \(error)")
                return false
            }
        case .enabled:
            logger.info("Daemon is enabled and ready")
            return true
        case .notFound:
            logger.error("Daemon not found in bundle")
            return false
        @unknown default:
            logger.error("Unknown daemon status: \(String(describing: currentStatus))")
            return false
        }
    }

    func openSystemSettingsForApproval() {
        logger.info("Opening System Settings for daemon approval")
        SMAppService.openSystemSettingsLoginItems()
    }

    func register() throws {
        logger.info("Attempting to register daemon")

        do {
            try service.register()
            logger.info("Daemon registered successfully")
        } catch {
            logger.error("Failed to register daemon: \(error)")

            let nsError = error as NSError
            if nsError.domain == "SMAppServiceErrorDomain" {
                switch nsError.code {
                case 1:
                    logger.info("Daemon already registered")
                    return
                case 2:
                    logger.error("Daemon job not found in bundle")
                case 3:
                    logger.warning("Daemon must be enabled by user in System Settings")
                case 4:
                    logger.error("Invalid daemon plist configuration")
                default:
                    logger.error("Unknown SMAppService error: \(nsError.code)")
                }
            }
            throw error
        }
    }

    func unregister() throws {
        logger.info("Attempting to unregister daemon")
        try service.unregister()
        logger.info("Daemon unregistered successfully")
    }
}
