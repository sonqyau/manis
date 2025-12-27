import Collections
@preconcurrency import Combine
import ComposableArchitecture
import DifferenceKit
import Foundation

@MainActor
struct ProvidersFeature: @preconcurrency Reducer {
    @ObservableState
    struct State {
        var selectedSegment: Int = 0
        var proxyProviders: OrderedDictionary<String, ProxyProviderInfo> = [:]
        var ruleProviders: OrderedDictionary<String, RuleProviderInfo> = [:]
        var refreshingProxyProviders: OrderedSet<String> = []
        var healthCheckingProxyProviders: OrderedSet<String> = []
        var refreshingRuleProviders: OrderedSet<String> = []
        var alert: AlertState<AlertAction>?
    }

    enum AlertAction: Equatable, DismissibleAlertAction {
        case dismissError
    }

    @CasePathable
    enum Action {
        case onAppear
        case onDisappear
        case selectSegment(Int)
        case refreshProxy(String)
        case healthCheckProxy(String)
        case refreshRule(String)
        case mihomoSnapshotUpdated(MihomoSnapshot)
        case refreshProxyFinished(name: String, error: String?)
        case healthCheckProxyFinished(name: String, error: String?)
        case refreshRuleFinished(name: String, error: String?)
        case alert(AlertAction)
    }

    private enum CancelID {
        case mihomoStream
    }

    @Dependency(\.mihomoService)
    var mihomoService

    init() {}

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return onAppearEffect()

            case .onDisappear:
                return .cancel(id: CancelID.mihomoStream)

            case let .mihomoSnapshotUpdated(snapshot):
                let stagedProxyProvidersChangeset = StagedChangeset(source: Array(state.proxyProviders.values), target: Array(snapshot.proxyProviders.values))
                for changeset in stagedProxyProvidersChangeset {
                    for delete in changeset.elementDeleted where delete.element < state.proxyProviders.count {
                        let keys = Array(state.proxyProviders.keys)
                        if delete.element < keys.count {
                            state.proxyProviders.removeValue(forKey: keys[delete.element])
                        }
                    }
                    for insert in changeset.elementInserted where insert.element < snapshot.proxyProviders.count {
                        let keys = Array(snapshot.proxyProviders.keys)
                        if insert.element < keys.count {
                            let key = keys[insert.element]
                            if let provider = snapshot.proxyProviders[key] {
                                state.proxyProviders[provider.name.rawValue] = provider
                            }
                        }
                    }
                    for update in changeset.elementUpdated where update.element < snapshot.proxyProviders.count {
                        let keys = Array(snapshot.proxyProviders.keys)
                        if update.element < keys.count {
                            let key = keys[update.element]
                            if let provider = snapshot.proxyProviders[key] {
                                state.proxyProviders[provider.name.rawValue] = provider
                            }
                        }
                    }
                }

                let stagedRuleProvidersChangeset = StagedChangeset(source: Array(state.ruleProviders.values), target: Array(snapshot.ruleProviders.values))
                for changeset in stagedRuleProvidersChangeset {
                    for delete in changeset.elementDeleted where delete.element < state.ruleProviders.count {
                        let keys = Array(state.ruleProviders.keys)
                        if delete.element < keys.count {
                            state.ruleProviders.removeValue(forKey: keys[delete.element])
                        }
                    }
                    for insert in changeset.elementInserted where insert.element < snapshot.ruleProviders.count {
                        let keys = Array(snapshot.ruleProviders.keys)
                        if insert.element < keys.count {
                            let key = keys[insert.element]
                            if let provider = snapshot.ruleProviders[key] {
                                state.ruleProviders[provider.name.rawValue] = provider
                            }
                        }
                    }
                    for update in changeset.elementUpdated where update.element < snapshot.ruleProviders.count {
                        let keys = Array(snapshot.ruleProviders.keys)
                        if update.element < keys.count {
                            let key = keys[update.element]
                            if let provider = snapshot.ruleProviders[key] {
                                state.ruleProviders[provider.name.rawValue] = provider
                            }
                        }
                    }
                }
                return .none

            case let .selectSegment(index):
                state.selectedSegment = index
                return .none

            case let .refreshProxy(name):
                return refreshProxyEffect(state: &state, name: name)

            case let .healthCheckProxy(name):
                return healthCheckProxyEffect(state: &state, name: name)

            case let .refreshRule(name):
                return refreshRuleEffect(state: &state, name: name)

            case let .refreshProxyFinished(name, error):
                state.refreshingProxyProviders.remove(name)
                if let error {
                    state.alert = .error(error)
                }
                return .none

            case let .healthCheckProxyFinished(name, error):
                state.healthCheckingProxyProviders.remove(name)
                if let error {
                    state.alert = .error(error)
                }
                return .none

            case let .refreshRuleFinished(name, error):
                state.refreshingRuleProviders.remove(name)
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

    private func refreshProxyEffect(
        state: inout State,
        name: String,
    ) -> Effect<Action> {
        guard !state.refreshingProxyProviders.contains(name) else {
            return .none
        }
        state.refreshingProxyProviders.append(name)

        let service = mihomoService
        return .run { @MainActor send in
            do {
                try await service.updateProxyProvider(name: name)
                send(.refreshProxyFinished(name: name, error: nil))
            } catch {
                let message = (error as NSError).localizedDescription
                send(.refreshProxyFinished(name: name, error: message))
            }
        }
    }

    private func healthCheckProxyEffect(
        state: inout State,
        name: String,
    ) -> Effect<Action> {
        guard !state.healthCheckingProxyProviders.contains(name) else {
            return .none
        }
        state.healthCheckingProxyProviders.append(name)

        let service = mihomoService
        return .run { @MainActor send in
            do {
                try await service.healthCheckProxyProvider(name: name)
                send(.healthCheckProxyFinished(name: name, error: nil))
            } catch {
                let message = (error as NSError).localizedDescription
                send(.healthCheckProxyFinished(name: name, error: message))
            }
        }
    }

    private func refreshRuleEffect(
        state: inout State,
        name: String,
    ) -> Effect<Action> {
        guard !state.refreshingRuleProviders.contains(name) else {
            return .none
        }
        state.refreshingRuleProviders.append(name)

        let service = mihomoService
        return .run { @MainActor send in
            do {
                try await service.updateRuleProvider(name: name)
                send(.refreshRuleFinished(name: name, error: nil))
            } catch {
                let message = (error as NSError).localizedDescription
                send(.refreshRuleFinished(name: name, error: message))
            }
        }
    }
}
