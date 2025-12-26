import ComposableArchitecture
import Foundation
import Sharing
import SwiftNavigation
import SwiftUI
import SwiftUINavigation

@MainActor
struct DashboardFeature: @preconcurrency Reducer {
    @ObservableState
    struct State {
        var selectedTab: DashboardTab?
        var overview: OverviewFeature.State = .init()
        var proxies: ProxiesFeature.State = .init()
        var connections: ConnectionsFeature.State = .init()
        var rules: RulesFeature.State = .init()
        var providers: ProvidersFeature.State = .init()
        var dns: DNSFeature.State = .init()
        var logs: LogsFeature.State = .init()

        var sharedSelectedTab: Shared<DashboardTab?> {
            Shared(wrappedValue: nil, .appStorage("selectedDashboardTab"))
        }
    }

    @CasePathable
    enum Action {
        case onAppear
        case onDisappear
        case selectTab(DashboardTab)
        case overview(OverviewFeature.Action)
        case proxies(ProxiesFeature.Action)
        case connections(ConnectionsFeature.Action)
        case rules(RulesFeature.Action)
        case providers(ProvidersFeature.Action)
        case dns(DNSFeature.Action)
        case logs(LogsFeature.Action)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.overview, action: \.overview) {
            OverviewFeature()
        }
        Scope(state: \.proxies, action: \.proxies) {
            ProxiesFeature()
        }
        Scope(state: \.connections, action: \.connections) {
            ConnectionsFeature()
        }
        Scope(state: \.rules, action: \.rules) {
            RulesFeature()
        }
        Scope(state: \.providers, action: \.providers) {
            ProvidersFeature()
        }
        Scope(state: \.dns, action: \.dns) {
            DNSFeature()
        }
        Scope(state: \.logs, action: \.logs) {
            LogsFeature()
        }

        Reduce { state, action in
            switch action {
            case .onAppear:
                if state.selectedTab == nil {
                    let defaultTab = DashboardTab.overview
                    state.selectedTab = defaultTab

                    return .run { @MainActor [sharedSelectedTab = state.sharedSelectedTab] _ in
                        sharedSelectedTab.withLock { $0 = defaultTab }
                    }
                }
                return .none

            case .onDisappear:
                return .none

            case let .selectTab(tab):
                state.selectedTab = tab

                return .run { @MainActor [sharedSelectedTab = state.sharedSelectedTab] _ in
                    sharedSelectedTab.withLock { $0 = tab }
                }

            case .overview:
                return .none

            case .proxies:
                return .none

            case .connections:
                return .none

            case .rules:
                return .none

            case .providers:
                return .none

            case .dns:
                return .none

            case .logs:
                return .none
            }
        }
    }

    init() {}
}
