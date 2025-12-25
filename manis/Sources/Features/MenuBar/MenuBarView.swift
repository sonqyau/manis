import Collections
import ComposableArchitecture
import Perception
import SFSafeSymbols
import SwiftNavigation
import SwiftUI
import SwiftUINavigation

struct MenuBarIconView: View {
    let store: StoreOf<MenuBarFeature>
    @Bindable private var bindableStore: StoreOf<MenuBarFeature>

    private var isActive: Bool {
        bindableStore.statusDescription == "Connected"
    }

    private var statusColor: Color {
        isActive ? .green : .red
    }

    init(store: StoreOf<MenuBarFeature>) {
        self.store = store
        _bindableStore = Bindable(wrappedValue: store)
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            VStack(alignment: .trailing, spacing: 0) {
                speedRow(icon: .arrowUp, speed: bindableStore.uploadSpeed)
                speedRow(icon: .arrowDown, speed: bindableStore.downloadSpeed)
            }
        }
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(statusColor)
        .contentTransition(.numericText())
        .task { bindableStore.send(.onAppear) }
        .onDisappear { bindableStore.send(.onDisappear) }
    }

    private func speedRow(icon: SFSymbol, speed: String) -> some View {
        HStack(spacing: 4) {
            Image(systemSymbol: icon)
                .font(.caption2)
                .accessibilityHidden(true)
            Text(speed)
        }
    }
}

struct MenuBarContentView: View {
    let store: StoreOf<MenuBarFeature>
    @Bindable private var bindableStore: StoreOf<MenuBarFeature>
    @Environment(\.openWindow)
    private var openWindow

    private var isActive: Bool {
        bindableStore.statusDescription == "Connected"
    }

    private var statusColor: Color {
        isActive ? .green : .secondary
    }

    init(store: StoreOf<MenuBarFeature>) {
        self.store = store
        _bindableStore = Bindable(wrappedValue: store)
    }

    var body: some View {
        Form {
            statusSection

            if !bindableStore.selectorGroups.isEmpty {
                proxyGroupsSection
            }

            quickActionsSection

            navigationSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .task { bindableStore.send(.onAppear) }
        .onDisappear { bindableStore.send(.onDisappear) }
        .alert(
            Binding<AlertState<MenuBarFeature.AlertAction>?>(
                get: { bindableStore.alert },
                set: { _ in },
                ),
            ) { action in
            if let action {
                bindableStore.send(.alert(action))
            }
        }
    }

    private var statusSection: some View {
        Section {
            statusSectionContent
        } header: {
            Label("Status", systemSymbol: .infoCircle)
        }
    }

    @ViewBuilder private var statusSectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor.gradient)
                    .frame(width: 10, height: 10)
                    .symbolEffect(.pulse, options: .repeating, isActive: isActive)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(bindableStore.statusDescription)
                        .font(.headline)

                    Text(bindableStore.statusSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let interface = bindableStore.networkInterface,
                   let ipAddress = bindableStore.ipAddress {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(interface)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(ipAddress)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                }
            }

            if bindableStore.mixedPort != nil || bindableStore.httpPort != nil || bindableStore.socksPort != nil {
                VStack(spacing: 8) {
                    HStack(spacing: 16) {
                        if let mixedPort = bindableStore.mixedPort {
                            portInfo(title: "Mixed", port: mixedPort, color: .blue)
                        }
                        if let httpPort = bindableStore.httpPort {
                            portInfo(title: "HTTP", port: httpPort, color: .green)
                        }
                        if let socksPort = bindableStore.socksPort {
                            portInfo(title: "SOCKS", port: socksPort, color: .orange)
                        }
                    }
                }
            }

            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    trafficStat(
                        icon: .arrowDown,
                        value: bindableStore.downloadSpeed,
                        color: .blue,
                        )
                    Divider().frame(height: 20)
                    trafficStat(
                        icon: .arrowUp,
                        value: bindableStore.uploadSpeed,
                        color: .green,
                        )
                    Divider().frame(height: 20)
                    memoryStat(value: bindableStore.memoryUsage)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func portInfo(title: String, port: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(color)
            Text("\(port)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    private func memoryStat(value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemSymbol: .memorychip)
                .foregroundColor(.purple)
                .font(.caption)
                .accessibilityHidden(true)
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }

    private func trafficStat(icon: SFSymbol, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemSymbol: icon)
                .foregroundColor(color)
                .font(.caption)
                .accessibilityHidden(true)
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }

    private func filterTile(
        title: String,
        icon: SFSymbol,
        isActive: Bool = false,
        activeColor: Color = .blue,
        ) -> some View {
        HStack(spacing: 8) {
            Image(systemSymbol: icon)
                .font(.body)
                .foregroundStyle(isActive ? activeColor : .primary)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption)
                .foregroundStyle(isActive ? activeColor : .primary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            isActive ? activeColor.opacity(0.15) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 10),
            )
    }

    private var proxyGroupsSection: some View {
        Section {
            ForEach(store.selectorGroups) { proxyGroup in
                MenuBarProxyGroupRow(
                    group: proxyGroup,
                    proxies: bindableStore.proxies,
                    ) { groupName, proxy in
                    bindableStore.send(.selectProxy(group: groupName, proxy: proxy))
                }
            }
        } header: {
            Label("Proxy groups", systemSymbol: .serverRack)
        }
    }

    private var quickActionsSection: some View {
        Section {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        bindableStore.send(.toggleSystemProxy)
                    } label: {
                        quickActionTile(
                            title: "System Proxy",
                            icon: .network,
                            isActive: bindableStore.systemProxyEnabled,
                            activeColor: .blue
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        bindableStore.send(.toggleTunMode)
                    } label: {
                        quickActionTile(
                            title: "TUN Mode",
                            icon: .shieldFill,
                            isActive: bindableStore.tunModeEnabled,
                            activeColor: .green
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    bindableStore.send(.reloadConfig)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemSymbol: .arrowClockwise)
                            .font(.body)
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text("Reload Config")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        Color.orange.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
                .buttonStyle(.plain)
            }
        } header: {
            Label("Actions", systemSymbol: .boltCircle)
        }
    }

    private func quickActionTile(
        title: String,
        icon: SFSymbol,
        isActive: Bool = false,
        activeColor: Color = .blue
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemSymbol: icon)
                .font(.body)
                .foregroundStyle(isActive ? activeColor : .primary)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption)
                .foregroundStyle(isActive ? activeColor : .primary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            isActive ? activeColor.opacity(0.15) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private var navigationSection: some View {
        Section {
            HStack(spacing: 8) {
                Button {
                    openWindow(id: "dashboardWindow")
                } label: {
                    filterTile(title: "Dashboard", icon: .squareGrid2x2Fill)
                }
                .buttonStyle(.plain)

                Button {
                    openWindow(id: "settingsWindow")
                } label: {
                    filterTile(title: "Settings", icon: .gear)
                }
                .buttonStyle(.plain)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    filterTile(title: "Quit", icon: .power)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Label("Shortcuts", systemSymbol: .arrowshapeTurnUpRightCircle)
        }
    }
}

struct MenuBarNavigationButton: View {
    let title: String
    let icon: SFSymbol
    var tint: Color?
    var showsChevron: Bool
    var role: ButtonRole?
    let action: () -> Void

    init(
        title: String,
        icon: SFSymbol,
        tint: Color? = nil,
        showsChevron: Bool = true,
        role: ButtonRole? = nil,
        action: @escaping () -> Void,
        ) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.showsChevron = showsChevron
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 8) {
                Label(title, systemSymbol: icon)
                    .foregroundStyle(tint ?? .primary)
                Spacer()
                if showsChevron {
                    Image(systemSymbol: .chevronRight)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill((tint ?? Color.secondary).opacity(0.08)),
                )
        }
        .buttonStyle(.plain)
    }
}

private struct MenuBarProxyGroupRow: View {
    let group: MenuBarFeature.State.ProxySelectorGroup
    let proxies: OrderedDictionary<String, ProxyInfo>
    let onSelect: (String, String) -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemSymbol: .chevronRight)
                        .font(.caption)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)

                    Text(group.info.name)
                        .font(.headline)

                    Spacer()

                    if let active = group.info.now {
                        Text(active)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    } else {
                        Text("Not Connected")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(group.info.all, id: \.self) { proxyName in
                        MenuBarProxyNodeRow(
                            proxyName: proxyName,
                            isSelected: proxyName == group.info.now,
                            proxyInfo: proxies[proxyName],
                            ) {
                            onSelect(group.id, proxyName)
                        }
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
    }
}

private struct MenuBarProxyNodeRow: View {
    let proxyName: String
    let isSelected: Bool
    let proxyInfo: ProxyInfo?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1),
                        )

                Text(proxyName)
                    .font(.body)

                Spacer()

                Text(delayDisplay)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(delayColor)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .padding(.leading, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var delay: Int? {
        proxyInfo?.history.last?.delay
    }

    private var delayDisplay: String {
        guard let delay else {
            return "--"
        }
        if delay == 0 {
            return "Timeout"
        }
        return "\(delay)ms"
    }

    private var delayColor: Color {
        guard let delay else {
            return .secondary
        }
        if delay == 0 {
            return .red
        }
        if delay < 300 {
            return .green
        }
        return .orange
    }

    private var statusColor: Color {
        if isSelected {
            return .accentColor
        }
        return delayColor == .secondary ? Color.secondary.opacity(0.6) : delayColor
    }
}

enum MenuBarView {}
