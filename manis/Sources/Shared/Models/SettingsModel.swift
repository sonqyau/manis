import Foundation
import SwiftData

@Model
final class SettingsModel {
    var apiPort = 9090
    var apiSecret = ""
    var externalControllerURL: String?

    var customGeoIPURL: String?
    var lastGeoIPUpdate: Date?

    var showNetworkSpeed = true
    var selectedConfigName = "config"
    var logLevel = "info"
    var launchAtLogin = false

    var benchmarkURL = "https://www.apple.com/library/test/success.html"
    var benchmarkTimeout = 5000
    var autoUpdateGeoIP = false
    var autoUpdateInterval: TimeInterval = 86400
    var lastSelectedTab = "overview"
    var dashboardRefreshInterval: TimeInterval = 5.0

    var createdAt = Date()
    var updatedAt = Date()

    init() {}

    func updateTimestamp() {
        updatedAt = Date()
    }
}

@MainActor
@Observable
final class SettingsManager {
    static let shared = SettingsManager()

    private(set) var modelContainer: ModelContainer?
    private(set) var settings: SettingsModel?

    private init() {}

    func initialize() throws {
        let schema = Schema([
            SettingsModel.self,
            PersistenceModel.self,
            RemoteInstance.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            )

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            modelContainer = container

            let context = container.mainContext
            let descriptor = FetchDescriptor<SettingsModel>()
            let existingSettings = try context.fetch(descriptor)

            if let existing = existingSettings.first {
                settings = existing
            } else {
                let newSettings = SettingsModel()
                context.insert(newSettings)
                try context.save()
                settings = newSettings
            }
        } catch {
            throw SettingsError.initializationFailed(error)
        }
    }

    func save() throws {
        guard let container = modelContainer else {
            throw SettingsError.notInitialized
        }

        settings?.updateTimestamp()
        try container.mainContext.save()
    }

    var showNetworkSpeed: Bool {
        get { settings?.showNetworkSpeed ?? true }
        set {
            settings?.showNetworkSpeed = newValue
            try? save()
        }
    }

    var showSpeedInMenuBar: Bool {
        get { settings?.showNetworkSpeed ?? true }
        set {
            settings?.showNetworkSpeed = newValue
            try? save()
        }
    }

    var selectedConfigName: String {
        get { settings?.selectedConfigName ?? "config" }
        set {
            settings?.selectedConfigName = newValue
            try? save()
        }
    }

    var customGeoIPURL: String? {
        get { settings?.customGeoIPURL }
        set {
            settings?.customGeoIPURL = newValue
            try? save()
        }
    }

    var launchAtLogin: Bool {
        get { settings?.launchAtLogin ?? false }
        set {
            settings?.launchAtLogin = newValue
            try? save()
        }
    }
}

enum SettingsError: MainError {
    case notInitialized
    case initializationFailed(any Error)

    static var errorDomain: String { NSError.applicationErrorDomain }

    var category: ErrorCategory { .state }

    var errorCode: Int {
        switch self {
        case .notInitialized: 8001
        case .initializationFailed: 8002
        }
    }

    var recoverySuggestion: String? { "Restart the application or check configuration" }
    var recoveryOptions: [String]? { ["Retry", "Reset", "Cancel"] }
    var helpAnchor: String? { "settings-errors" }

    var userFriendlyMessage: String {
        errorDescription ?? "Settings configuration error"
    }

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            "Settings manager has not been initialized"

        case let .initializationFailed(error):
            "Unable to initialize settings: \(error.localizedDescription)"
        }
    }

    var failureReason: String? {
        switch self {
        case .notInitialized:
            "The settings system has not been properly initialized"
        case .initializationFailed:
            "Settings initialization process encountered an error"
        }
    }
}
