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
    }

    enum AlertAction: Equatable {
        case dismissError
    }

    enum Action: Equatable {
        case onAppear
        case alert(AlertAction)
        case openSystemSettings
        case confirmBootstrap
        case toggleBootstrap

        case refreshDaemonStatus
        case installDaemon
        case uninstallDaemon

        case refreshKernelStatus
        case startKernel
        case stopKernel

        case kernelStatusUpdated(State.KernelStatusSnapshot)
        case kernelStatusFailed(String)

        case operationFinished(String?)
    }

    @Dependency(\.settingsService)
    var settingsService

    @Dependency(\.resourceService)
    var resourceService

    @Dependency(\.mihomoService)
    var mihomoService

    init() {}

    var body: some ReducerOf<Self> {
        Reduce { state, action in
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
                state.alert = AlertState {
                    TextState("Error")
                } actions: {
                    ButtonState(action: .dismissError) {
                        TextState("OK")
                    }
                } message: {
                    TextState(message)
                }
                return .none

            case .startKernel:
                return startKernelEffect(state: &state)

            case .stopKernel:
                return stopKernelEffect(state: &state)
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

        return .none
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
                try DaemonManager.shared.register()
                send(.refreshDaemonStatus)
                send(.operationFinished(nil))
            } catch {
                send(.refreshDaemonStatus)
                send(.operationFinished((error as NSError).localizedDescription))
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
            return "Installed"
        case .requiresApproval:
            return "Requires Approval"
        case .notRegistered:
            return "Not Installed"
        case .notFound:
            return "Not Found"
        @unknown default:
            return "Unknown"
        }
    }

    private func operationFinishedEffect(
        state: inout State,
        errorMessage: String?,
    ) -> Effect<Action> {
        state.isProcessing = false
        if let errorMessage {
            state.alert = AlertState {
                TextState("Error")
            } actions: {
                ButtonState(action: .dismissError) {
                    TextState("OK")
                }
            } message: {
                TextState(errorMessage)
            }
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
}
