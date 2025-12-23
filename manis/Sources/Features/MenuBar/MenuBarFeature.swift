@preconcurrency import Combine
import Collections
import ComposableArchitecture
import Foundation
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
    }

    enum AlertAction: Equatable {
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
            return .none

        case let .selectProxy(group, proxy):
            return selectProxyEffect(group: group, proxy: proxy)

        case let .selectProxyFinished(error):
            if let error {
                state.alert = AlertState {
                    TextState("Error")
                } actions: {
                    ButtonState(action: .dismissError) {
                        TextState("OK")
                    }
                } message: {
                    TextState(error)
                }
            }
            return .none

        case let .operationFinished(errorMessage):
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
            return .none
        }
    }

    private func onAppearEffect(state: inout State) -> Effect<Action> {
        let mihomo = mihomoService
        let network = networkService

        let mihomoEffect: Effect<Action> = .run { @MainActor send in
            for await domainState in mihomo.statePublisher.values {
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

    private func runOperation(
        containerDescription _: String,
        work: @escaping () async throws -> Void,
    ) -> Effect<Action> {
        .run { @MainActor send in
            do {
                try await work()
                send(.operationFinished(nil))
            } catch {
                let message = (error as NSError).localizedDescription
                send(.operationFinished(message))
            }
        }
    }

    private static func formatSpeed(_ value: String?) -> String {
        value ?? "0 B/s"
    }

    private static func buildSelectorGroups(
        from groups: OrderedDictionary<String, GroupInfo>
    ) -> [State.ProxySelectorGroup] {
        groups
            .filter { $0.value.type.lowercased() == "selector" }
            .sorted { $0.key < $1.key }
            .map { key, info in
                State.ProxySelectorGroup(id: key, info: info)
            }
    }
}
