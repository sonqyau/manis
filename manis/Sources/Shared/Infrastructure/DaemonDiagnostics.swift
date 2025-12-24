import Foundation
import ServiceManagement
import OSLog

@MainActor
struct DaemonDiagnostics {
    private let logger = Logger(subsystem: "com.manis.app", category: "DaemonDiagnostics")

    func diagnose() -> DiagnosticReport {
        logger.info("Starting daemon diagnostics")

        var report = DiagnosticReport()

        let daemonManager = DaemonManager.shared
        report.smAppServiceStatus = daemonManager.status

        report.bundleStructure = checkBundleStructure()

        report.legacyInstallation = checkLegacyInstallation()

        report.xpcServiceStatus = checkXPCServiceStatus()

        report.systemPermissions = checkSystemPermissions()

        logger.info("Diagnostics complete: \(report.summary)")
        return report
    }

    private func checkBundleStructure() -> BundleStructureStatus {
        let bundle = Bundle.main

        let daemonPlistPath = bundle.path(forResource: "com.manis.Daemon", ofType: nil, inDirectory: "Library/LaunchDaemons")
        let daemonBinaryPath = bundle.path(forResource: "com.manis.Daemon", ofType: nil, inDirectory: "Library/LaunchServices")
        let xpcPlistPath = bundle.path(forResource: "com.manis.XPC", ofType: "plist", inDirectory: "Library/LaunchServices")
        let xpcBinaryPath = bundle.path(forResource: "MainXPC", ofType: nil, inDirectory: "Library/LaunchServices")

        var issues: [String] = []

        if daemonPlistPath == nil {
            issues.append("Daemon plist not found in bundle")
        }
        if daemonBinaryPath == nil {
            issues.append("Daemon binary not found in bundle")
        }
        if xpcPlistPath == nil {
            issues.append("XPC plist not found in bundle")
        }
        if xpcBinaryPath == nil {
            issues.append("XPC binary not found in bundle")
        }

        return issues.isEmpty ? .valid : .invalid(issues.joined(separator: ", "))
    }

    private func checkLegacyInstallation() -> LegacyInstallationStatus {
        let legacyPlistPath = "/Library/LaunchDaemons/com.manis.Daemon.plist"
        let legacyHelperPath = "/Library/PrivilegedHelperTools/com.manis.Daemon"

        let plistExists = FileManager.default.fileExists(atPath: legacyPlistPath)
        let helperExists = FileManager.default.fileExists(atPath: legacyHelperPath)

        if plistExists || helperExists {
            return .present(plist: plistExists, helper: helperExists)
        } else {
            return .absent
        }
    }

    private func checkXPCServiceStatus() -> XPCServiceStatus {
        let connection = NSXPCConnection(machServiceName: "com.manis.XPC")
        connection.remoteObjectInterface = NSXPCInterface(with: MainXPCProtocol.self)

        var connectionEstablished = false
        let semaphore = DispatchSemaphore(value: 0)

        connection.invalidationHandler = {
            connectionEstablished = false
            semaphore.signal()
        }

        connection.interruptionHandler = {
            connectionEstablished = false
            semaphore.signal()
        }

        connection.resume()

        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            connectionEstablished = false
            semaphore.signal()
        }

        if proxy is MainXPCProtocol {
            connectionEstablished = true
        }

        connection.invalidate()

        return connectionEstablished ? .available : .unavailable
    }

    private func checkSystemPermissions() -> SystemPermissionsStatus {
        guard let entitlements = Bundle.main.object(forInfoDictionaryKey: "com.apple.security.temporary-exception.mach-lookup.global-name") as? [String] else {
            return .insufficient("Missing mach lookup entitlements")
        }

        if !entitlements.contains("com.manis.Daemon") {
            return .insufficient("Missing daemon mach service entitlement")
        }

        return .sufficient
    }
}

struct DiagnosticReport {
    var smAppServiceStatus: SMAppService.Status = .notFound
    var bundleStructure: BundleStructureStatus = .unknown
    var legacyInstallation: LegacyInstallationStatus = .unknown
    var xpcServiceStatus: XPCServiceStatus = .unknown
    var systemPermissions: SystemPermissionsStatus = .unknown

    var summary: String {
        return """
        SMAppService: \(smAppServiceStatus)
        Bundle: \(bundleStructure)
        Legacy: \(legacyInstallation)
        XPC: \(xpcServiceStatus)
        Permissions: \(systemPermissions)
        """
    }

    var recommendations: [String] {
        var recs: [String] = []

        switch smAppServiceStatus {
        case .requiresApproval:
            recs.append("Enable daemon in System Settings > Login Items")
        case .notRegistered:
            recs.append("Register daemon using Install Daemon button")
        case .notFound:
            recs.append("Check app bundle structure and rebuild")
        case .enabled:
            break
        @unknown default:
            recs.append("Unknown daemon status - try reinstalling")
        }

        if case .invalid(let reason) = bundleStructure {
            recs.append("Fix bundle structure: \(reason)")
        }

        if case .present = legacyInstallation {
            recs.append("Clean up legacy installation before using SMAppService")
        }

        if case .unavailable = xpcServiceStatus {
            recs.append("XPC service unavailable - check daemon status")
        }

        if case .insufficient(let reason) = systemPermissions {
            recs.append("Fix permissions: \(reason)")
        }

        return recs
    }
}

enum BundleStructureStatus {
    case valid
    case invalid(String)
    case unknown
}

enum LegacyInstallationStatus {
    case present(plist: Bool, helper: Bool)
    case absent
    case unknown
}

enum XPCServiceStatus {
    case available
    case unavailable
    case unknown
}

enum SystemPermissionsStatus {
    case sufficient
    case insufficient(String)
    case unknown
}
