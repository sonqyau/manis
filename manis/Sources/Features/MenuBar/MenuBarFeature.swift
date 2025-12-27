import AsyncAlgorithms
import Collections
@preconcurrency import Combine
import ComposableArchitecture
import Foundation
import NonEmpty
import SwiftNavigation

@MainActor
struct MenuBarFeature: @preconcurrency Reducer {
    @ObservableState
    struct State {
        struct ProxySelectorGroup: Identifiable {
            var id: String
            var info: GroupInfo
        }

        var statusDescription: String = "Ready"
        var statusSubtitle: String = ""

        var downloadSpeed: String = "--"
        var uploadSpeed: String = "--"
        var selectorGroups: [ProxySelectorGroup] = []
        var proxies: OrderedDictionary<String, ProxyInfo> = [:]
        var networkInterface: String?
        var ipAddress: String?
        var alert: AlertState<AlertAction>?

        var systemProxyEnabled: Bool = false
        var tunModeEnabled: Bool = false

        var mixedPort: Int?
        var httpPort: Int?
        var socksPort: Int?

        var memoryUsage: String = "--"
    }

    enum AlertAction: Equatable, DismissibleAlertAction {
        case dismissError
    }

    @CasePathable
    enum Action {
        case onAppear
        case onDisappear
        case selectProxy(group: String, proxy: String)
        case refreshNetworkInfo
        case mihomoSnapshotUpdated(MihomoSnapshot)

        case selectProxyFinished(error: String?)
        case operationFinished(String?)
        case alert(AlertAction)

        case toggleSystemProxy
        case toggleTunMode
        case reloadConfig

        case systemProxyToggled(Bool, String?)
        case tunModeToggled(Bool, String?)
        case configReloaded(String?)
    }

    private enum CancelID {
        case mihomoStream
    }

    @Dependency(\.mihomoService)
    var mihomoService

    @Dependency(\.networkService)
    var networkService

    @Dependency(\.resourceService)
    var resourceService

    init() {}

    var body: some ReducerOf<Self> {
        Reduce(reduce(into:action:))
    }

    func reduce(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .onAppear:
            return onAppearEffect(state: &state)

        case .onDisappear:
            return onDisappearEffect()

        case .alert(.dismissError):
            state.alert = nil
            return .none

        case .refreshNetworkInfo:
            state.networkInterface = networkService.getPrimaryInterfaceName()
            state.ipAddress = networkService.getPrimaryIPAddress(allowIPv6: false)
            return .none

        case let .mihomoSnapshotUpdated(snapshot):
            state.downloadSpeed = Self.formatSpeed(snapshot.currentTraffic?.downloadSpeed)
            state.uploadSpeed = Self.formatSpeed(snapshot.currentTraffic?.uploadSpeed)
            state.selectorGroups = Self.buildSelectorGroups(from: snapshot.groups)
            state.proxies = snapshot.proxies
            state.statusDescription = snapshot.isConnected ? "Connected" : "Disconnected"

            if let config = snapshot.config {
                state.mixedPort = config.mixedPort?.rawValue
                state.httpPort = config.port?.rawValue
                state.socksPort = config.socksPort?.rawValue
            }

            if let config = snapshot.config {
                state.systemProxyEnabled = snapshot.isConnected && (config.port != nil || config.mixedPort != nil)
                state.tunModeEnabled = false
            }

            state.memoryUsage = Self.formatMemory(snapshot.memoryUsage)

            return .none

        case let .selectProxy(group, proxy):
            return selectProxyEffect(group: group, proxy: proxy)

        case let .selectProxyFinished(error):
            if let error {
                state.alert = .error(error)
            }
            return .none

        case let .operationFinished(errorMessage):
            if let errorMessage {
                state.alert = .error(errorMessage)
            }
            return .none

        case .toggleSystemProxy:
            return toggleSystemProxyEffect(currentState: state.systemProxyEnabled)

        case .toggleTunMode:
            return toggleTunModeEffect(currentState: state.tunModeEnabled)

        case .reloadConfig:
            return reloadConfigEffect()

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

        case let .configReloaded(error):
            if let error {
                state.alert = .error(error)
            }
            return .none
        }
    }

    private func onAppearEffect(state: inout State) -> Effect<Action> {
        let mihomo = mihomoService
        let network = networkService

        let mihomoEffect: Effect<Action> = .run { @MainActor send in
            let debouncedStream = mihomo.statePublisher.values
                .debounce(for: .milliseconds(300))

            for await domainState in debouncedStream {
                let snapshot = MihomoSnapshot(domainState)
                send(.mihomoSnapshotUpdated(snapshot))
            }
        }
        .cancellable(id: CancelID.mihomoStream, cancelInFlight: true)

        state.networkInterface = network.getPrimaryInterfaceName()
        state.ipAddress = network.getPrimaryIPAddress(allowIPv6: false)

        return .merge(mihomoEffect)
    }

    private func onDisappearEffect() -> Effect<Action> {
        .merge(
            .cancel(id: CancelID.mihomoStream),
        )
    }

    private func selectProxyEffect(group: String, proxy: String) -> Effect<Action> {
        let service = mihomoService
        return .run { @MainActor send in
            do {
                try await service.selectProxy(group: group, proxy: proxy)
                send(.selectProxyFinished(error: nil))
            } catch {
                let message = (error as NSError).localizedDescription
                send(.selectProxyFinished(error: message))
            }
        }
    }

    private static func formatSpeed(_ value: String?) -> String {
        value ?? "0 B/s"
    }

    private static func formatMemory(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: bytes)
    }

    private static func buildSelectorGroups(
        from groups: OrderedDictionary<String, GroupInfo>,
    ) -> [State.ProxySelectorGroup] {
        let filteredGroups = groups
            .filter { $0.value.type.lowercased() == "selector" }
            .sorted { $0.key < $1.key }
            .map { key, info in
                State.ProxySelectorGroup(id: key, info: info)
            }

        return filteredGroups
    }

    private func toggleSystemProxyEffect(currentState: Bool) -> Effect<Action> {
        let service = mihomoService
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

    private func toggleTunModeEffect(currentState: Bool) -> Effect<Action> {
        let service = mihomoService
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

    private func reloadConfigEffect() -> Effect<Action> {
        let service = mihomoService
        return .run { @MainActor send in
            do {
                try await service.reloadConfig(path: "", payload: "")
                send(.configReloaded(nil))
            } catch {
                let message = (error as NSError).localizedDescription
                send(.configReloaded(message))
            }
        }
    }
}
