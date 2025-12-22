import Foundation

@MainActor
protocol SettingsService: AnyObject, Sendable {
    func initialize() throws

    var launchAtLogin: Bool { get set }
}

@MainActor
final class SettingsManagerServiceAdapter: SettingsService, @unchecked Sendable {
    private let manager: SettingsManager

    init(manager: SettingsManager = .shared) {
        self.manager = manager
    }

    func initialize() throws {
        try manager.initialize()
    }

    var launchAtLogin: Bool {
        get { manager.launchAtLogin }
        set { manager.launchAtLogin = newValue }
    }
}
