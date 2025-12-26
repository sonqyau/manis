import Collections
@preconcurrency import Combine
import ComposableArchitecture
import DifferenceKit
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

    enum AlertAction: Equatable, DismissibleAlertAction {
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
                let stagedGroupsChangeset = StagedChangeset(source: Array(state.groups.values), target: Array(snapshot.groups.values))
                for changeset in stagedGroupsChangeset {
                    for delete in changeset.elementDeleted where delete.element < state.groups.count {
                        let keys = Array(state.groups.keys)
                        if delete.element < keys.count {
                            state.groups.removeValue(forKey: keys[delete.element])
                        }
                    }
                    for insert in changeset.elementInserted where insert.element < snapshot.groups.count {
                        let keys = Array(snapshot.groups.keys)
                        if insert.element < keys.count {
                            let key = keys[insert.element]
                            if let group = snapshot.groups[key] {
                                state.groups[group.name.rawValue] = group
                            }
                        }
                    }
                    for update in changeset.elementUpdated where update.element < snapshot.groups.count {
                        let keys = Array(snapshot.groups.keys)
                        if update.element < keys.count {
                            let key = keys[update.element]
                            if let group = snapshot.groups[key] {
                                state.groups[group.name.rawValue] = group
                            }
                        }
                    }
                }

                let stagedProxiesChangeset = StagedChangeset(source: Array(state.proxies.values), target: Array(snapshot.proxies.values))
                for changeset in stagedProxiesChangeset {
                    for delete in changeset.elementDeleted where delete.element < state.proxies.count {
                        let keys = Array(state.proxies.keys)
                        if delete.element < keys.count {
                            state.proxies.removeValue(forKey: keys[delete.element])
                        }
                    }
                    for insert in changeset.elementInserted where insert.element < snapshot.proxies.count {
                        let keys = Array(snapshot.proxies.keys)
                        if insert.element < keys.count {
                            let key = keys[insert.element]
                            if let proxy = snapshot.proxies[key] {
                                state.proxies[proxy.name.rawValue] = proxy
                            }
                        }
                    }
                    for update in changeset.elementUpdated where update.element < snapshot.proxies.count {
                        let keys = Array(snapshot.proxies.keys)
                        if update.element < keys.count {
                            let key = keys[update.element]
                            if let proxy = snapshot.proxies[key] {
                                state.proxies[proxy.name.rawValue] = proxy
                            }
                        }
                    }
                }
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
                    state.alert = .error(error)
                }
                return .none

            case let .testGroupDelayFinished(group, error):
                state.testingGroups.remove(group)
                if let error {
                    state.alert = .error(error)
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
