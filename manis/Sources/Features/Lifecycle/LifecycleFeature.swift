import AppKit
import ComposableArchitecture
import Foundation
import SwiftData
import UserNotifications

@MainActor
struct LifecycleFeature: @preconcurrency Reducer {
    struct State: Equatable {}

    enum Action {
        case initialize
        case shutdown
    }

    @Dependency(\.settingsService)
    var settingsService

    @Dependency(\.persistenceService)
    var persistenceService

    @Dependency(\.resourceService)
    var resourceService

    @Dependency(\.mihomoService)
    var mihomoService

    @Dependency(\.networkService)
    var networkService

    init() {}

    func reduce(into _: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .initialize:
            return .run { @MainActor _ in
                let context = InitializationContext(
                    settingsService: settingsService,
                    persistenceService: persistenceService,
                    resourceService: resourceService,
                    mihomoService: mihomoService,
                    networkService: networkService,
                    )
                await Self.initializeApplication(context)
            }

        case .shutdown:
            let networkService = networkService
            let mihomoService = mihomoService

            return .run { @MainActor _ in
                networkService.stopMonitoring()
                mihomoService.disconnect()
            }
        }
    }

    struct InitializationContext {
        let settingsService: SettingsService
        let persistenceService: PersistenceService
        let resourceService: ResourceService
        let mihomoService: MihomoService
        let networkService: NetworkService
    }

    @MainActor
    private static func initializeApplication(_ context: InitializationContext) async {
        var initializationWarnings: [String] = []

        await requestNotificationPermissions()

        do {
            try context.settingsService.initialize()
        } catch {
            await showInitializationError(error)
            return
        }

        if let container = SettingsManager.shared.modelContainer {
            await performRecoverableStep(
                "Remote configuration setup",
                warning: "Remote configuration unavailable. Local mode is enabled.",
                initializationWarnings: &initializationWarnings,
                ) {
                try context.persistenceService.initialize(container: container)
            }
        }

        await performRecoverableStep(
            "Resource initialization",
            warning: "Resource directory incomplete. Geo data or configuration synchronization may be limited.",
            initializationWarnings: &initializationWarnings,
            ) {
            try await context.resourceService.initialize()
        }

        await performRecoverableStep(
            "Default configuration initialization",
            warning: "Failed to generate the default configuration. Verify write permissions.",
            initializationWarnings: &initializationWarnings,
            ) {
            try context.resourceService.ensureDefaultConfig()
        }

        context.networkService.startMonitoring()

        await presentInitializationWarnings(initializationWarnings)
    }

    @MainActor
    private static func requestNotificationPermissions() async {
        guard Bundle.main.bundleIdentifier != nil else {
            return
        }

        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])

            if granted {
                let action = UNNotificationAction(
                    identifier: "RELOAD_CONFIG",
                    title: "Reload",
                    options: [.foreground],
                    )
                let category = UNNotificationCategory(
                    identifier: "CONFIG_CHANGE",
                    actions: [action],
                    intentIdentifiers: [],
                    )
                center.setNotificationCategories([category])
            }
        } catch {}
    }

    @MainActor
    private static func showInitializationError(_ error: any Error) async {
        let alert = NSAlert()
        alert.messageText = "Initialization Failed"
        alert.informativeText = error.applicationMessage
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Exit")

        if let suggestion = error.applicationRecoverySuggestion {
            alert.informativeText += "\n\n\(suggestion)"
        }

        alert.runModal()
        NSApplication.shared.terminate(nil)
    }

    @MainActor
    private static func performRecoverableStep(
        _: String,
        warning: String,
        initializationWarnings: inout [String],
        operation: () async throws -> Void,
        ) async {
        do {
            try await operation()
        } catch {
            recordInitializationWarning(
                warning,
                error: error,
                initializationWarnings: &initializationWarnings,
                )
        }
    }

    @MainActor
    private static func recordInitializationWarning(
        _ message: String,
        error: any Error,
        initializationWarnings: inout [String],
        ) {
        initializationWarnings.append("\(message) (Reason: \(error.applicationMessage))")
    }

    @MainActor
    private static func presentInitializationWarnings(_ initializationWarnings: [String]) async {
        guard !initializationWarnings.isEmpty else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Limited Functionality"
        let joined = initializationWarnings.map { "• \($0)" }.joined(separator: "\n")
        alert.informativeText = joined
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")

        alert.runModal()
    }
}
