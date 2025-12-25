import ComposableArchitecture
import Foundation
import Perception
import SwiftNavigation

@MainActor
struct SettingsFeature: @preconcurrency Reducer {
    @ObservableState
    struct State: Equatable {
        struct KernelStatusSnapshot: Equatable {
            var isRunning: Bool
            var processId: Int32
            var externalController: String?
            var secret: String?
        }

        struct StatusOverview: Equatable {
            var indicatorIsActive: Bool = false
            var summary: String = "Disabled"
            var hint: String?
        }

        struct Bootstrap: Equatable {
            var isEnabled: Bool = false
            var requiresApproval: Bool = false
        }

        var statusOverview: StatusOverview = .init()
        var launchAtLogin: Bootstrap = .init()

        var kernelIsRunning: Bool = false
        var kernelController: String?
        var kernelSecret: String?

        var daemonStatus: String = "Unknown"

        var alert: AlertState<AlertAction>?
        var isProcessing: Bool = false
        var isPerformingSystemOperation: Bool = false

        var systemProxyEnabled: Bool = false
        var tunModeEnabled: Bool = false
        var mixedPort: Int?
        var httpPort: Int?
        var socksPort: Int?
        var memoryUsage: String = "--"
        var trafficInfo: String = "--"
        var version: String = "--"
    }

    enum AlertAction: Equatable, DismissibleAlertAction {
        case dismissError
    }

    @CasePathable
    enum Action: Equatable {
        case onAppear
        case alert(AlertAction)
        case openSystemSettings
        case confirmBootstrap
        case toggleBootstrap

        case refreshDaemonStatus
        case installDaemon
        case uninstallDaemon
        case diagnoseDaemon

        case refreshKernelStatus
        case startKernel
        case stopKernel

        case restartCore
        case upgradeCore
        case upgradeUI
        case upgradeGeo
        case systemOperationFinished(Bool, String?)

        case kernelStatusUpdated(State.KernelStatusSnapshot)
        case kernelStatusFailed(String)

        case operationFinished(String?)

        case toggleSystemProxy
        case toggleTunMode
        case flushFakeIPCache
        case flushDNSCache
        case triggerGC
        case mihomoSnapshotUpdated(MihomoSnapshot)

        case systemProxyToggled(Bool, String?)
        case tunModeToggled(Bool, String?)
        case cacheOperationFinished(String?)

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.onAppear, .onAppear),
                 (.alert, .alert),
                 (.openSystemSettings, .openSystemSettings),
                 (.confirmBootstrap, .confirmBootstrap),
                 (.refreshDaemonStatus, .refreshDaemonStatus),
                 (.installDaemon, .installDaemon),
                 (.uninstallDaemon, .uninstallDaemon),
                 (.refreshKernelStatus, .refreshKernelStatus),
                 (.startKernel, .startKernel),
                 (.stopKernel, .stopKernel),
                 (.restartCore, .restartCore),
                 (.upgradeCore, .upgradeCore),
                 (.upgradeUI, .upgradeUI),
                 (.upgradeGeo, .upgradeGeo),
                 (.kernelStatusUpdated, .kernelStatusUpdated),
                 (.kernelStatusFailed, .kernelStatusFailed),
                 (.operationFinished, .operationFinished),
                 (.toggleSystemProxy, .toggleSystemProxy),
                 (.toggleTunMode, .toggleTunMode),
                 (.flushFakeIPCache, .flushFakeIPCache),
                 (.flushDNSCache, .flushDNSCache),
                 (.triggerGC, .triggerGC),
                 (.mihomoSnapshotUpdated, .mihomoSnapshotUpdated),
                 (.systemProxyToggled, .systemProxyToggled),
                 (.tunModeToggled, .tunModeToggled),
                 (.cacheOperationFinished, .cacheOperationFinished):
                true
            case (.toggleBootstrap, .toggleBootstrap):
                true
            case let (.systemOperationFinished(lhsSuccess, lhsError), .systemOperationFinished(rhsSuccess, rhsError)):
                lhsSuccess == rhsSuccess && lhsError == rhsError
            default:
                false
            }
        }
    }

    @Dependency(\.settingsService)
    var settingsService

    @Dependency(\.resourceService)
    var resourceService

    @Dependency(\.mihomoService)
    var mihomoService

    init() {}

    var body: some ReducerOf<Self> {
        Reduce { (state: inout State, action: Action) -> Effect<Action> in
            switch action {
            case .onAppear:
                return onAppearEffect(state: &state)

            case .alert(.dismissError):
                state.alert = nil
                return .none

            case let .operationFinished(errorMessage):
                return operationFinishedEffect(state: &state, errorMessage: errorMessage)

            case .confirmBootstrap:
                let launchState = LaunchSnapshot()
                state.launchAtLogin = .init(
                    isEnabled: launchState.isEnabled,
                    requiresApproval: launchState.requiresApproval,
                    )
                return .none

            case .toggleBootstrap:
                return toggleBootstrapEffect(state: &state)

            case .openSystemSettings:
                Bootstrap.openSystemSettings()
                return .none

            case .refreshDaemonStatus:
                return refreshDaemonStatusEffect(state: &state)

            case .installDaemon:
                return installDaemonEffect(state: &state)

            case .uninstallDaemon:
                return uninstallDaemonEffect(state: &state)

            case .diagnoseDaemon:
                return diagnoseDaemonEffect(state: &state)

            case .refreshKernelStatus:
                return refreshKernelStatusEffect(state: &state)

            case let .kernelStatusUpdated(snapshot):
                let previousController = state.kernelController
                let previousSecret = state.kernelSecret

                state.kernelIsRunning = snapshot.isRunning
                state.kernelController = snapshot.externalController
                state.kernelSecret = snapshot.secret

                applyKernelStatusToMihomoService(
                    statusIsRunning: snapshot.isRunning,
                    externalController: snapshot.externalController,
                    secret: snapshot.secret,
                    previousController: previousController,
                    previousSecret: previousSecret,
                    state: &state,
                    )

                state.statusOverview = .init(
                    indicatorIsActive: snapshot.isRunning,
                    summary: snapshot.isRunning ? "Kernel Running" : "Kernel Stopped",
                    hint: snapshot.externalController,
                    )

                state.isProcessing = false
                return .none

            case let .kernelStatusFailed(message):
                state.isProcessing = false
                state.alert = .error(message)
                return .none

            case .startKernel:
                return startKernelEffect(state: &state)

            case .stopKernel:
                return stopKernelEffect(state: &state)

            case .restartCore:
                return restartCoreEffect(state: &state)

            case .upgradeCore:
                return upgradeCoreEffect(state: &state)

            case .upgradeUI:
                return upgradeUIEffect(state: &state)

            case .upgradeGeo:
                return upgradeGeoEffect(state: &state)

            case let .systemOperationFinished(success, errorMessage):
                return systemOperationFinishedEffect(state: &state, success: success, errorMessage: errorMessage)

            case .toggleSystemProxy:
                return toggleSystemProxyEffect(state: &state)

            case .toggleTunMode:
                return toggleTunModeEffect(state: &state)

            case .flushFakeIPCache:
                return flushFakeIPCacheEffect(state: &state)

            case .flushDNSCache:
                return flushDNSCacheEffect(state: &state)

            case .triggerGC:
                return triggerGCEffect(state: &state)

            case let .mihomoSnapshotUpdated(snapshot):
                if let config = snapshot.config {
                    state.mixedPort = config.mixedPort
                    state.httpPort = config.port
                    state.socksPort = config.socksPort
                    state.systemProxyEnabled = snapshot.isConnected && (config.port != nil || config.mixedPort != nil)
                    state.tunModeEnabled = false
                }
                state.memoryUsage = formatMemory(snapshot.memoryUsage)
                state.trafficInfo = formatTraffic(snapshot.currentTraffic)
                state.version = snapshot.version
                return .none

            case let .systemProxyToggled(enabled, error):
                state.systemProxyEnabled = enabled
                if let error {
                    state.alert = .error(error)
                }
                return .none

            case let .tunModeToggled(enabled, error):
                state.tunModeEnabled = enabled
                if let error {
                    state.alert = .error(error)
                }
                return .none

            case let .cacheOperationFinished(error):
                if let error {
                    state.alert = .error(error)
                }
                return .none
            }
        }
    }

    private func onAppearEffect(state: inout State) -> Effect<Action> {
        let launchState = LaunchSnapshot()

        state.statusOverview = .init(
            indicatorIsActive: false,
            summary: "Ready",
            hint: nil,
            )

        state.launchAtLogin = .init(
            isEnabled: launchState.isEnabled,
            requiresApproval: launchState.requiresApproval,
            )

        state.daemonStatus = describeDaemonStatus()

        let mihomo = mihomoService
        let mihomoEffect: Effect<Action> = .run { @MainActor send in
            for await domainState in mihomo.statePublisher.values {
                let snapshot = MihomoSnapshot(domainState)
                send(.mihomoSnapshotUpdated(snapshot))
            }
        }
        .cancellable(id: "mihomoStream", cancelInFlight: true)

        return mihomoEffect
    }

    private func refreshDaemonStatusEffect(state: inout State) -> Effect<Action> {
        state.daemonStatus = describeDaemonStatus()
        return .none
    }

    private func installDaemonEffect(state: inout State) -> Effect<Action> {
        guard !state.isProcessing else {
            return .none
        }
        state.isProcessing = true
        state.alert = nil

        return .run { @MainActor send in
            do {
                let daemonManager = DaemonManager.shared
                let currentStatus = daemonManager.status

                switch currentStatus {
                case .requiresApproval:
                    send(.operationFinished("Daemon requires approval in System Settings. Opening Login Items..."))
                    daemonManager.openSystemSettingsForApproval()
                    return

                case .enabled:
                    send(.refreshDaemonStatus)
                    send(.operationFinished(nil))
                    return

                case .notRegistered, .notFound:
                    let newStatus = daemonManager.status
                    if newStatus == .requiresApproval {
                        send(.operationFinished("Daemon installed but requires approval. Opening System Settings..."))
                        daemonManager.openSystemSettingsForApproval()
                    } else if newStatus == .enabled {
                        send(.operationFinished("Daemon installed successfully"))
                    } else {
                        send(.operationFinished("Daemon installed but status unclear. Please check System Settings."))
                    }

                @unknown default:
                    throw NSError(
                        domain: "com.manis.app",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Unknown daemon status"],
                        )
                }

                send(.refreshDaemonStatus)
            } catch {
                send(.refreshDaemonStatus)
                let errorMessage = (error as NSError).localizedDescription
                send(.operationFinished("Installation failed: \(errorMessage)"))
            }
        }
    }

    private func uninstallDaemonEffect(state: inout State) -> Effect<Action> {
        guard !state.isProcessing else {
            return .none
        }
        state.isProcessing = true
        state.alert = nil

        return .run { @MainActor send in
            do {
                try DaemonManager.shared.unregister()
                send(.refreshDaemonStatus)
                send(.operationFinished(nil))
            } catch {
                send(.refreshDaemonStatus)
                send(.operationFinished((error as NSError).localizedDescription))
            }
        }
    }

    private func describeDaemonStatus() -> String {
        switch DaemonManager.shared.status {
        case .enabled:
            return "Installed & Enabled"
        case .requiresApproval:
            return "Requires User Approval"
        case .notRegistered:
            return "Not Installed"
        case .notFound:
            return "Not Found in Bundle"
        @unknown default:
            return "Unknown Status"
        }
    }

    private func diagnoseDaemonEffect(state: inout State) -> Effect<Action> {
        guard !state.isProcessing else {
            return .none
        }
        state.isProcessing = true
        state.alert = nil

        return .run { @MainActor send in
            let diagnostics = DaemonDiagnostics()
            let report = diagnostics.diagnose()

            let message = """
            Daemon Diagnostics:

            \(report.summary)

            Recommendations:
            \(report.recommendations.isEmpty ? "No issues found" : report.recommendations.joined(separator: "\n"))
            """

            send(.operationFinished(message))
        }
    }

    private func operationFinishedEffect(
        state: inout State,
        errorMessage: String?,
        ) -> Effect<Action> {
        state.isProcessing = false
        if let errorMessage {
            state.alert = .error(errorMessage)
        }

        state.daemonStatus = describeDaemonStatus()

        let launchState = LaunchSnapshot()
        state.launchAtLogin = .init(
            isEnabled: launchState.isEnabled,
            requiresApproval: launchState.requiresApproval,
            )
        return .none
    }

    private func toggleBootstrapEffect(state: inout State) -> Effect<Action> {
        guard !state.isProcessing else {
            return .none
        }
        state.isProcessing = true
        state.alert = nil

        return .run { @MainActor send in
            Bootstrap.isEnabled.toggle()
            let enabled = Bootstrap.isEnabled
            settingsService.launchAtLogin = enabled
            send(.confirmBootstrap)
            send(.operationFinished(nil))
        }
    }

    private func refreshKernelStatusEffect(state: inout State) -> Effect<Action> {
        guard !state.isProcessing else {
            return .none
        }

        state.isProcessing = true
        state.alert = nil

        return .run { @MainActor send in
            do {
                let status = try await XPCClient().getKernelStatus()
                send(
                    .kernelStatusUpdated(
                        .init(
                            isRunning: status.isRunning,
                            processId: status.processId,
                            externalController: status.externalController,
                            secret: status.secret,
                            ),
                        ),
                    )
            } catch {
                let message = (error as NSError).localizedDescription
                send(.kernelStatusFailed(message))
            }
        }
    }

    private func startKernelEffect(state: inout State) -> Effect<Action> {
        guard !state.isProcessing else {
            return .none
        }

        state.isProcessing = true
        state.alert = nil

        let configURL = resourceService.configFilePath
        let configDir = resourceService.configDirectory

        return .run { @MainActor send in
            do {
                let daemonManager = DaemonManager.shared
                let daemonStatus = daemonManager.status

                switch daemonStatus {
                case .notRegistered, .notFound:
                    send(.operationFinished("Daemon not installed. Please install daemon first."))
                    return

                case .requiresApproval:
                    send(.operationFinished("Daemon requires approval in System Settings. Please enable it in Login Items."))
                    daemonManager.openSystemSettingsForApproval()
                    return

                case .enabled:
                    break

                @unknown default:
                    send(.operationFinished("Unknown daemon status. Please reinstall daemon."))
                    return
                }

                let configContent = try String(contentsOf: configURL, encoding: .utf8)
                let executablePath = try findMihomoExecutablePath()
                try await XPCClient().startKernel(
                    executablePath: executablePath,
                    configPath: configDir.path,
                    configContent: configContent,
                    )
                send(.refreshKernelStatus)
            } catch {
                let message = (error as NSError).localizedDescription
                send(.operationFinished(message))
            }
        }
    }

    private func stopKernelEffect(state: inout State) -> Effect<Action> {
        guard !state.isProcessing else {
            return .none
        }

        state.isProcessing = true
        state.alert = nil

        return .run { @MainActor send in
            do {
                try await XPCClient().stopKernel()
                send(.refreshKernelStatus)
            } catch {
                let message = (error as NSError).localizedDescription
                send(.operationFinished(message))
            }
        }
    }

    private func findMihomoExecutablePath() throws -> String {
        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL
                .appendingPathComponent("Kernel", isDirectory: true)
                .appendingPathComponent("binary")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate.path
            }
        }

        throw NSError(domain: "com.manis", code: -100, userInfo: [NSLocalizedDescriptionKey: "kernel binary not found in app bundle (Resources/Kernel/binary)"])
    }

    private func applyKernelStatusToMihomoService(
        statusIsRunning: Bool,
        externalController: String?,
        secret: String?,
        previousController: String?,
        previousSecret: String?,
        state: inout State,
        ) {
        if !statusIsRunning {
            if state.statusOverview.indicatorIsActive {
                mihomoService.disconnect()
            }
            return
        }

        guard let externalController, !externalController.isEmpty else {
            return
        }

        let baseURL = "http://\(externalController)"
        let didChange = previousController != externalController || previousSecret != secret

        guard didChange else {
            return
        }

        mihomoService.disconnect()
        mihomoService.configure(baseURL: baseURL, secret: secret)
    }

    private func restartCoreEffect(state: inout State) -> Effect<Action> {
        guard !state.isPerformingSystemOperation else {
            return .none
        }
        state.isPerformingSystemOperation = true
        state.alert = nil

        return .run { @MainActor send in
            do {
                try await mihomoService.restart()
                send(.systemOperationFinished(true, nil))
            } catch {
                send(.systemOperationFinished(false, (error as NSError).localizedDescription))
            }
        }
    }

    private func upgradeCoreEffect(state: inout State) -> Effect<Action> {
        guard !state.isPerformingSystemOperation else {
            return .none
        }
        state.isPerformingSystemOperation = true
        state.alert = nil

        return .run { @MainActor send in
            do {
                try await mihomoService.upgradeCore()
                send(.systemOperationFinished(true, nil))
            } catch {
                send(.systemOperationFinished(false, (error as NSError).localizedDescription))
            }
        }
    }

    private func upgradeUIEffect(state: inout State) -> Effect<Action> {
        guard !state.isPerformingSystemOperation else {
            return .none
        }
        state.isPerformingSystemOperation = true
        state.alert = nil

        return .run { @MainActor send in
            do {
                try await mihomoService.upgradeUI()
                send(.systemOperationFinished(true, nil))
            } catch {
                send(.systemOperationFinished(false, (error as NSError).localizedDescription))
            }
        }
    }

    private func upgradeGeoEffect(state: inout State) -> Effect<Action> {
        guard !state.isPerformingSystemOperation else {
            return .none
        }
        state.isPerformingSystemOperation = true
        state.alert = nil

        return .run { @MainActor send in
            do {
                try await mihomoService.upgradeGeo2()
                send(.systemOperationFinished(true, nil))
            } catch {
                try await mihomoService.upgradeGeo1()
                send(.systemOperationFinished(false, (error as NSError).localizedDescription))
            }
        }
    }

    private func systemOperationFinishedEffect(
        state: inout State,
        success: Bool,
        errorMessage: String?,
        ) -> Effect<Action> {
        state.isPerformingSystemOperation = false

        if success {
            state.alert = .success("Operation completed successfully")
        } else if let errorMessage {
            state.alert = .error(errorMessage)
        }

        return .none
    }

    private func toggleSystemProxyEffect(state: inout State) -> Effect<Action> {
        let service = mihomoService
        let currentState = state.systemProxyEnabled
        return .run { @MainActor send in
            do {
                let newState = !currentState
                let updates: [String: Any] = [
                    "port": newState ? 7890 : 0,
                    "mixed-port": newState ? 7890 : 0,
                ]

                try await service.updateConfig(updates)
                send(.systemProxyToggled(newState, nil))
            } catch {
                let message = (error as NSError).localizedDescription
                send(.systemProxyToggled(currentState, message))
            }
        }
    }

    private func toggleTunModeEffect(state: inout State) -> Effect<Action> {
        let service = mihomoService
        let currentState = state.tunModeEnabled
        return .run { @MainActor send in
            do {
                let newState = !currentState
                let tunConfig: [String: Any] = [
                    "enable": newState,
                    "stack": "system",
                    "auto-route": newState,
                    "auto-detect-interface": newState,
                ]
                let updates: [String: Any] = ["tun": tunConfig]

                try await service.updateConfig(updates)
                send(.tunModeToggled(newState, nil))
            } catch {
                let message = (error as NSError).localizedDescription
                send(.tunModeToggled(currentState, message))
            }
        }
    }

    private func flushFakeIPCacheEffect(state _: inout State) -> Effect<Action> {
        let service = mihomoService
        return .run { @MainActor send in
            do {
                try await service.flushFakeIPCache()
                send(.cacheOperationFinished(nil))
            } catch {
                let message = (error as NSError).localizedDescription
                send(.cacheOperationFinished(message))
            }
        }
    }

    private func flushDNSCacheEffect(state _: inout State) -> Effect<Action> {
        let service = mihomoService
        return .run { @MainActor send in
            do {
                try await service.flushDNSCache()
                send(.cacheOperationFinished(nil))
            } catch {
                let message = (error as NSError).localizedDescription
                send(.cacheOperationFinished(message))
            }
        }
    }

    private func triggerGCEffect(state _: inout State) -> Effect<Action> {
        let service = mihomoService
        return .run { @MainActor send in
            do {
                try await service.triggerGC()
                send(.cacheOperationFinished(nil))
            } catch {
                let message = (error as NSError).localizedDescription
                send(.cacheOperationFinished(message))
            }
        }
    }

    private func formatMemory(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: bytes)
    }

    private func formatTraffic(_ traffic: TrafficSnapshot?) -> String {
        guard let traffic else { return "--" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        let down = formatter.string(fromByteCount: Int64(traffic.down))
        let up = formatter.string(fromByteCount: Int64(traffic.up))
        return "↓\(down) ↑\(up)"
    }
}
