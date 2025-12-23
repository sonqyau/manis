import Collections
import ComposableArchitecture
import Perception
import SwiftNavigation
import SwiftUI
import SwiftUIIntrospect

struct ProxiesView: View {
    let store: StoreOf<ProxiesFeature>
    @Bindable private var bindableStore: StoreOf<ProxiesFeature>
    @FocusState private var isSearchFocused: Bool

    init(store: StoreOf<ProxiesFeature>) {
        self.store = store
        _bindableStore = Bindable(wrappedValue: store)
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { bindableStore.searchText },
            set: { bindableStore.send(.updateSearch($0)) },
        )
    }

    private var filteredGroups: [(String, GroupInfo)] {
        let groups = bindableStore.groups.sorted { $0.key < $1.key }
        guard !bindableStore.searchText.isEmpty else {
            return groups
        }
        return groups.filter { $0.key.localizedCaseInsensitiveContains(bindableStore.searchText) }
    }

    var body: some View {
        Form {
            searchSection

            Section {
                EmptyView()
                    .if(filteredGroups.isEmpty) { _ in
                        ContentUnavailableView {
                            Label("No Proxy Groups", systemImage: "rectangle.stack.fill")
                        } description: {
                            Text("No proxy groups are available.")
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                    }
                    .ifNot(filteredGroups.isEmpty) { _ in
                        ForEach(filteredGroups, id: \.0) { name, group in
                            ProxyGroupCard(
                                name: name,
                                group: group,
                                proxies: bindableStore.proxies,
                                onSelectProxy: { proxyName in
                                    bindableStore.send(.selectProxy(group: name, proxy: proxyName))
                                },
                                onTestDelay: {
                                    bindableStore.send(.testGroupDelay(name))
                                },
                            )
                        }
                    }
            } header: {
                Label("Proxy Groups", systemImage: "rectangle.stack")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Proxy groups")
        .task { bindableStore.send(.onAppear) }
        .onDisappear { bindableStore.send(.onDisappear) }
        .alert(
            Binding<AlertState<ProxiesFeature.AlertAction>?>(
                get: { bindableStore.alert },
                set: { _ in },
            ),
        ) { action in
            if let action {
                bindableStore.send(.alert(action))
            }
        }
    }

    private var searchSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField("Search", text: searchBinding)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)

                EmptyView()
                    .if(!bindableStore.searchText.isEmpty) { _ in
                        Button {
                            bindableStore.send(.updateSearch(""))
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .accessibilityLabel("Clear search filter")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
            }
            .padding(.vertical, 8)
        } header: {
            Label("Search", systemImage: "text.magnifyingglass")
        }
    }
}

private struct ProxyGroupCard: View {
    let name: String
    let group: GroupInfo
    let proxies: OrderedDictionary<String, ProxyInfo>
    let onSelectProxy: (String) -> Void
    let onTestDelay: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.smooth) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.smooth, value: isExpanded)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .font(.headline)

                        HStack(spacing: 8) {
                            Text(group.type)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let now = group.now {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text(now)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }

                    Spacer()

                    Button {
                        onTestDelay()
                    } label: {
                        Label("Test Delay", systemImage: "speedometer")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 8) {
                    if !group.all.isEmpty {
                        ForEach(group.all, id: \.self) { proxyName in
                            ProxyNodeRow(
                                proxyName: proxyName,
                                isSelected: proxyName == group.now,
                                proxyInfo: proxies[proxyName],
                            ) { onSelectProxy(proxyName) }
                        }
                    } else {
                        Text("No proxies are available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    }
                }
                .padding(.leading, 22)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct ProxyNodeRow: View {
    let proxyName: String
    let isSelected: Bool
    let proxyInfo: ProxyInfo?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Circle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1),
                    )

                Text(proxyName)
                    .font(.body)

                Spacer()

                if let delay = proxyInfo?.history.last?.delay {
                    Text(formatDelay(delay))
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            Color(delay == 0 ? .red : delay < 100 ? .green : delay < 300 ? .orange : .red)
                                .opacity(0.15),
                            in: Capsule(),
                        )
                        .foregroundStyle(Color(delay == 0
                                ? .red
                                : delay < 100 ? .green : delay < 300 ? .orange : .red))
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                isSelected ? Color.accentColor.opacity(0.1) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8),
            )
        }
        .buttonStyle(.plain)
    }

    private func formatDelay(_ delay: Int) -> String {
        if delay == 0 {
            return "Timeout"
        }
        return "\(delay)ms"
    }
}
