import Charts
import ComposableArchitecture
import Perception
import SwiftNavigation
import SwiftUI
import SwiftUIIntrospect
import SwiftUINavigation

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview
    case proxies
    case connections
    case rules
    case providers
    case dns
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .proxies: "Proxies"
        case .connections: "Connections"
        case .rules: "Rules"
        case .providers: "Providers"
        case .dns: "DNS"
        case .logs: "Logs"
        }
    }

    var icon: String {
        switch self {
        case .overview: "chart.bar.fill"
        case .proxies: "arrow.triangle.branch"
        case .connections: "network"
        case .rules: "list.bullet"
        case .providers: "externaldrive.fill"
        case .dns: "globe"
        case .logs: "doc.text.fill"
        }
    }
}

struct DashboardView: View {
    let store: StoreOf<DashboardFeature>
    @Bindable private var bindableStore: StoreOf<DashboardFeature>
    @State private var keyboardMonitor: NSObjectProtocol?

    init(store: StoreOf<DashboardFeature>) {
        self.store = store
        _bindableStore = Bindable(wrappedValue: store)
    }

    private var navigationPathBinding: Binding<NavigationPath> {
        Binding(
            get: { bindableStore.navigationPath },
            set: { path in
                bindableStore.send(.navigationPathChanged(path))
            },
            )
    }

    private var sidebar: some View {
        List(DashboardTab.allCases) { tab in
            NavigationLink(value: tab) {
                Label(tab.title, systemImage: tab.icon)
            }
        }
        .navigationTitle("Dashboard")
        .frame(minWidth: 200)
    }

    private var detail: some View {
        NavigationStack(path: navigationPathBinding) {
            VStack {
                if bindableStore.navigationPath.isEmpty {
                    Text("Select a tab to get started")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
            }
            .frame(minWidth: 600, minHeight: 400)
            .navigationDestination(for: DashboardTab.self) { tab in
                destinationView(for: tab)
            }
        }
    }

    @ViewBuilder
    private func destinationView(for tab: DashboardTab) -> some View {
        switch tab {
        case .overview:
            OverviewView(store: store.scope(state: \.overview, action: \.overview))

        case .proxies:
            ProxiesView(store: store.scope(state: \.proxies, action: \.proxies))

        case .connections:
            ConnectionsView(store: store.scope(state: \.connections, action: \.connections))

        case .rules:
            RulesView(store: store.scope(state: \.rules, action: \.rules))

        case .providers:
            ProvidersView(store: store.scope(state: \.providers, action: \.providers))

        case .dns:
            DNSView(store: store.scope(state: \.dns, action: \.dns))

        case .logs:
            LogsView(store: store.scope(state: \.logs, action: \.logs))
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .onAppear { bindableStore.send(.onAppear) }
        .onDisappear {
            bindableStore.send(.onDisappear)
            if let monitor = keyboardMonitor {
                NSEvent.removeMonitor(monitor)
                keyboardMonitor = nil
            }
        }
        .introspect(.view, on: .macOS(.v26)) { _ in
            if keyboardMonitor == nil {
                keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard event.modifierFlags.contains(.command),
                          NSApp.mainWindow?.isKeyWindow == true else { return event }

                    switch event.keyCode {
                    case 18:
                        bindableStore.send(.navigateToTab(.overview))
                    case 19:
                        bindableStore.send(.navigateToTab(.proxies))
                    case 20:
                        bindableStore.send(.navigateToTab(.connections))
                    case 21:
                        bindableStore.send(.navigateToTab(.rules))
                    case 23:
                        bindableStore.send(.navigateToTab(.providers))
                    case 22:
                        bindableStore.send(.navigateToTab(.dns))
                    case 26:
                        bindableStore.send(.navigateToTab(.logs))
                    default:
                        return event
                    }

                    return nil
                } as? NSObjectProtocol
            }
        }
    }
}
