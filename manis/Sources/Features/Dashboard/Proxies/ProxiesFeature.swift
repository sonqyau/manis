@preconcurrency import Combine
import Collections
import ComposableArchitecture
import Foundation
import SwiftNavigation

@MainActor
struct ProxiesFeature: @preconcurrency Reducer {
    @ObservableState
    struct State {
        var searchText: String = ""
        var groups: OrderedDictionary<String, GroupInfo> = [:]
        var proxies: OrderedDictionary<String, ProxyInfo> = [:]
        var selectingProxies: OrderedSet<String> = []
        var testingGroups: OrderedSet<String> = []
        var alert: AlertState<AlertAction>?
    }

    enum AlertAction: Equatable {
        case dismissError
    }

    @CasePathable
    enum Action {
        case onAppear
        case onDisappear
        case updateSearch(String)
        case selectProxy(group: String, proxy: String)
        case testGroupDelay(String)
        case mihomoSnapshotUpdated(MihomoSnapshot)
        case selectProxyFinished(key: String, error: String?)
        case testGroupDelayFinished(group: String, error: String?)
        case alert(AlertAction)
    }

    private enum CancelID {
        case mihomoStream
    }

    init() {}

    @Dependency(\.mihomoService)
    var mihomoService

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return onAppearEffect()

            case .onDisappear:
                return .cancel(id: CancelID.mihomoStream)

            case let .mihomoSnapshotUpdated(snapshot):
                state.groups = snapshot.groups
                state.proxies = snapshot.proxies
                return .none

            case let .updateSearch(text):
                if state.searchText != text {
                    state.searchText = text
                }
                return .none

            case let .selectProxy(group, proxy):
                return selectProxyEffect(state: &state, group: group, proxy: proxy)

            case let .testGroupDelay(group):
                return testGroupDelayEffect(state: &state, group: group)

            case let .selectProxyFinished(key, error):
                state.selectingProxies.remove(key)
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

            case let .testGroupDelayFinished(group, error):
                state.testingGroups.remove(group)
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

            case .alert(.dismissError):
                state.alert = nil
                return .none
            }
        }
    }

    private func onAppearEffect() -> Effect<Action> {
        let service = mihomoService
        return .run { @MainActor send in
            service.requestDashboardRefresh()
            for await domainState in service.statePublisher.values {
                let snapshot = MihomoSnapshot(domainState)
                send(.mihomoSnapshotUpdated(snapshot))
            }
        }
        .cancellable(id: CancelID.mihomoStream, cancelInFlight: true)
    }

    private func selectProxyEffect(
        state: inout State,
        group: String,
        proxy: String,
    ) -> Effect<Action> {
        let key = Self.proxySelectionKey(group: group, proxy: proxy)
        guard !state.selectingProxies.contains(key) else {
            return .none
        }
        state.selectingProxies.append(key)

        let service = mihomoService
        return .run { @MainActor send in
            do {
                try await service.selectProxy(group: group, proxy: proxy)
                send(.selectProxyFinished(key: key, error: nil))
            } catch {
                let message = (error as NSError).localizedDescription
                send(.selectProxyFinished(key: key, error: message))
            }
        }
    }

    private func testGroupDelayEffect(
        state: inout State,
        group: String,
    ) -> Effect<Action> {
        guard !state.testingGroups.contains(group) else {
            return .none
        }
        state.testingGroups.append(group)

        let service = mihomoService
        return .run { @MainActor send in
            do {
                try await service.testGroupDelay(name: group)
                send(.testGroupDelayFinished(group: group, error: nil))
            } catch {
                let message = (error as NSError).localizedDescription
                send(.testGroupDelayFinished(group: group, error: message))
            }
        }
    }

    private static func proxySelectionKey(group: String, proxy: String) -> String {
        "\(group)::\(proxy)"
    }
}
