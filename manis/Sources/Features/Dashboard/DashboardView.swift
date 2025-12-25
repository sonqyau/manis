import AsyncQueue
import Charts
import ComposableArchitecture
import Perception
import SFSafeSymbols
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

    var icon: SFSymbol {
        switch self {
        case .overview: .chartBarFill
        case .proxies: .arrowTriangleheadBranch
        case .connections: .network
        case .rules: .listBullet
        case .providers: .externaldriveFill
        case .dns: .globe
        case .logs: .textDocumentFill
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

    private var sidebar: some View {
        List(DashboardTab.allCases) { tab in
            Button {
                bindableStore.send(.selectTab(tab))
            } label: {
                Label(tab.title, systemSymbol: tab.icon)
                    .if(bindableStore.selectedTab == tab) { $0.foregroundColor(.accentColor) }
                    .ifNot(bindableStore.selectedTab == tab) { $0.foregroundColor(.primary) }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Dashboard")
        .frame(minWidth: 200)
    }

    private var detail: some View {
        VStack {
            if let selectedTab = bindableStore.selectedTab {
                destinationView(for: selectedTab)
            } else {
                Text("Select a tab to get started")
                    .foregroundColor(.secondary)
                    .font(.title2)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
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
            LogsMainView(store: store.scope(state: \.logs, action: \.logs))
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .onAppear {
            bindableStore.send(.onAppear)
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
            }
        }
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
                        bindableStore.send(.selectTab(.overview))
                    case 19:
                        bindableStore.send(.selectTab(.proxies))
                    case 20:
                        bindableStore.send(.selectTab(.connections))
                    case 21:
                        bindableStore.send(.selectTab(.rules))
                    case 23:
                        bindableStore.send(.selectTab(.providers))
                    case 22:
                        bindableStore.send(.selectTab(.dns))
                    case 26:
                        bindableStore.send(.selectTab(.logs))
                    default:
                        return event
                    }

                    return nil
                } as? NSObjectProtocol
            }
        }
    }
}
