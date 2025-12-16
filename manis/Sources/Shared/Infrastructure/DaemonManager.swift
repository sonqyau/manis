import Foundation
import ServiceManagement

@MainActor
final class DaemonManager {
    static let shared = DaemonManager()

    private let helperPlistName = "com.manis.Daemon"

    private init() {}

    private var service: SMAppService {
        SMAppService.daemon(plistName: helperPlistName)
    }

    var status: SMAppService.Status {
        service.status
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}
