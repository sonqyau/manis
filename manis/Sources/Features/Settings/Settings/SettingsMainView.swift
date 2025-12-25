import ComposableArchitecture
import Perception
import SFSafeSymbols
import SwiftNavigation
import SwiftUI

struct SettingsMainView: View {
    @Bindable private var store: StoreOf<SettingsFeature>
    let persistenceStore: StoreOf<PersistenceFeature>

    @State private var showingConfigEditor = false
    @State private var configContent = ""

    init(store: StoreOf<SettingsFeature>, persistenceStore: StoreOf<PersistenceFeature>) {
        _store = Bindable(wrappedValue: store)
        self.persistenceStore = persistenceStore
    }

    private var daemonSection: some View {
        Section {
            HStack(spacing: 12) {
                Button {
                    store.send(.installDaemon)
                } label: {
                    Label("Install", systemSymbol: .arrowDownCircle)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.state.isProcessing)

                Button {
                    store.send(.uninstallDaemon)
                } label: {
                    Label("Uninstall", systemSymbol: .trash)
                }
                .buttonStyle(.bordered)
                .disabled(store.state.isProcessing)

                Button {
                    store.send(.refreshDaemonStatus)
                } label: {
                    Label("Refresh", systemSymbol: .arrowClockwise)
                }
                .buttonStyle(.bordered)
                .disabled(store.state.isProcessing)
            }

            HStack {
                Text("Status")
                Spacer()
                Text(store.state.daemonStatus)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("Privileged Helper", systemSymbol: .lockShield)
        } footer: {
            Text("Required for kernel start/stop operations.")
                .foregroundStyle(.secondary)
        }
    }

    private var kernelSection: some View {
        Section {
            HStack(spacing: 12) {
                Button {
                    store.send(store.state.kernelIsRunning ? .stopKernel : .startKernel)
                } label: {
                    Label(store.state.kernelIsRunning ? "Stop Kernel" : "Start Kernel", systemSymbol: store.state.kernelIsRunning ? .stopCircle : .playCircle)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.state.isProcessing)

                Button {
                    store.send(.refreshKernelStatus)
                } label: {
                    Label("Refresh Status", systemSymbol: .arrowClockwise)
                }
                .buttonStyle(.bordered)
                .disabled(store.state.isProcessing)
            }
        } header: {
            Label("Kernel Management", systemSymbol: .cpu)
        } footer: {
            Text("Manis communicates with the privileged helper indirectly.")
                .foregroundStyle(.secondary)
        }
    }

    private var systemManagementSection: some View {
        Section {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        store.send(.restartCore)
                    } label: {
                        Label("Restart Core", systemSymbol: .arrowClockwise)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.state.isPerformingSystemOperation || !store.state.kernelIsRunning)

                    Button {
                        store.send(.upgradeCore)
                    } label: {
                        Label("Upgrade Core", systemSymbol: .arrowUpCircle)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.state.isPerformingSystemOperation || !store.state.kernelIsRunning)
                }

                HStack(spacing: 12) {
                    Button {
                        store.send(.upgradeUI)
                    } label: {
                        Label("Upgrade UI", systemSymbol: .paintbrush)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.state.isPerformingSystemOperation || !store.state.kernelIsRunning)

                    Button {
                        store.send(.upgradeGeo)
                    } label: {
                        Label("Upgrade GEO", systemSymbol: .globe)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.state.isPerformingSystemOperation || !store.state.kernelIsRunning)
                }

                if store.state.isPerformingSystemOperation {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Executing system operation...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
        } header: {
            Label("System Operations", systemSymbol: .wrenchAndScrewdriver)
        } footer: {
            Text("Core system management functions require active kernel connection.")
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                launchAtLoginSection
                daemonSection
                kernelSection
                proxySettingsSection
                systemManagementSection
                cacheManagementSection
                systemInfoSection
                configurationSection
                aboutSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .overlay {
                EmptyView()
                    .if(store.state.isProcessing) { _ in
                        progressOverlay
                    }
            }
            .navigationTitle("Settings")
        }
        .task {
            store.send(.onAppear)
        }
        .alert(
            Binding<AlertState<SettingsFeature.AlertAction>?>(
                get: { store.alert },
                set: { _ in },
                ),
            ) { action in
            if let action {
                store.send(.alert(action))
            }
        }
        .sheet(isPresented: $showingConfigEditor) {
            ConfigEditorWindow(
                fileName: "config.yaml",
                fileExtension: "yaml",
                language: .yaml,
                initialContent: configContent,
                )
        }
    }

    private var statusSection: some View {
        let status = store.state.statusOverview

        return Section {
            HStack(spacing: 16) {
                Circle()
                    .fill(status.indicatorIsActive ? Color.green.gradient : Color.secondary.gradient)
                    .frame(width: 12, height: 12)
                    .symbolEffect(.pulse, options: .repeating, isActive: status.indicatorIsActive)

                VStack(alignment: .leading, spacing: 2) {
                    Text(status.summary)
                        .font(.headline)

                    EmptyView()
                        .if(let: status.hint) { _, hint in
                            Text(hint)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                }

                Spacer()
            }
        } header: {
            Label("System Status", systemSymbol: .infoCircle)
        }
    }

    private var launchAtLoginSection: some View {
        Section {
            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { store.state.launchAtLogin.isEnabled },
                    set: { _ in store.send(.toggleBootstrap) },
                    ),
                )
            .toggleStyle(.switch)
            .disabled(store.state.isProcessing)

            EmptyView()
                .if(store.state.launchAtLogin.requiresApproval) { _ in
                    helperApprovalNotice(text: "Authorize Mihomo in Login Items within System Settings")
                    helperApprovalActions(needsStatusRefresh: false)
                }
        } header: {
            Label("System Startup", systemSymbol: .powerCircle)
        } footer: {
            Text("Launch Manis automatically during macOS login.")
                .foregroundStyle(.secondary)
        }
    }

    private var configurationSection: some View {
        Section {
            NavigationLink {
                PersistenceView(store: persistenceStore)
            } label: {
                HStack {
                    Label("Manage Configurations", systemSymbol: .textDocumentFill)
                    Spacer()
                    Image(systemSymbol: .chevronRight)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)

            Button {
                openConfigEditor()
            } label: {
                HStack {
                    Label("Edit Local Configuration", systemSymbol: .textDocument)
                    Spacer()
                    Image(systemSymbol: .pencil)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Label("Application Configuration", systemSymbol: .gear)
        } footer: {
            Text("Manage local and remote Mihomo configuration profiles, or directly edit the local configuration.")
                .foregroundStyle(.secondary)
        }
    }

    private func openConfigEditor() {
        if let configURL = Bundle.main.url(forResource: "config", withExtension: "yaml") {
            do {
                configContent = try String(contentsOf: configURL, encoding: .utf8)
                print("Config loaded from Resources: \(configContent.count) characters")
            } catch {
                print("Failed to load config from Resources: \(error)")
                configContent = getDefaultConfigContent()
            }
        } else {
            print("config.yaml not found in Resources, using default content")
            configContent = getDefaultConfigContent()
        }

        showingConfigEditor = true
    }

    private func getDefaultConfigContent() -> String {
        """

        port: 7890
        socks-port: 7891
        allow-lan: false
        mode: rule
        log-level: info

        external-controller: 127.0.0.1:9090

        dns:
          enable: true
          listen: 0.0.0.0:53
          default-nameserver:
            - 114.114.114.114
            - 8.8.8.8
          nameserver:
            - https://doh.pub/dns-query
            - https://dns.alidns.com/dns-query

        proxies:

        proxy-groups:

        rules:
          - MATCH,DIRECT
        """
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version") {
                Text("1.0.0")
                    .font(.body)
            }

            Link(
                destination:
                    URL(string: "https://github.com/sonqyau/manis") ??
                    URL(string: "https://github.com/sonqyau") ?? URL(fileURLWithPath: "/"),
                ) {
                HStack {
                    Label("GitHub Repository", systemSymbol: .link)
                    Spacer()
                    Image(systemSymbol: .arrowUpRight)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Opens in browser")
                }
            }
            .buttonStyle(.plain)
        } header: {
            Label("About", systemSymbol: .infoCircle)
        }
    }

    private var proxySettingsSection: some View {
        Section {
            Toggle(
                "System Proxy",
                isOn: Binding(
                    get: { store.state.systemProxyEnabled },
                    set: { _ in store.send(.toggleSystemProxy) },
                    ),
                )
            .toggleStyle(.switch)
            .disabled(store.state.isProcessing || !store.state.kernelIsRunning)

            Toggle(
                "TUN Mode",
                isOn: Binding(
                    get: { store.state.tunModeEnabled },
                    set: { _ in store.send(.toggleTunMode) },
                    ),
                )
            .toggleStyle(.switch)
            .disabled(store.state.isProcessing || !store.state.kernelIsRunning)

            if store.state.mixedPort != nil || store.state.httpPort != nil || store.state.socksPort != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if let mixedPort = store.state.mixedPort {
                        portInfoRow(title: "Mixed Port", value: "\(mixedPort)", detail: "Combined HTTP(S) and SOCKS proxy port")
                    }
                    if let httpPort = store.state.httpPort {
                        portInfoRow(title: "HTTP Port", value: "\(httpPort)", detail: "HTTP(S) proxy server port")
                    }
                    if let socksPort = store.state.socksPort {
                        portInfoRow(title: "SOCKS Port", value: "\(socksPort)", detail: "SOCKS5 proxy server port")
                    }
                }
            }
        } header: {
            Label("Network Configuration", systemSymbol: .network)
        } footer: {
            Text("Configure proxy modes and view port assignments. System proxy supports TCP-only HTTP connections.")
                .foregroundStyle(.secondary)
        }
    }

    private var cacheManagementSection: some View {
        Section {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        store.send(.flushFakeIPCache)
                    } label: {
                        Label("Clear Fake IP Cache", systemSymbol: .trashCircle)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.state.isProcessing || !store.state.kernelIsRunning)

                    Button {
                        store.send(.flushDNSCache)
                    } label: {
                        Label("Clear DNS Cache", systemSymbol: .trashCircleFill)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.state.isProcessing || !store.state.kernelIsRunning)
                }

                Button {
                    store.send(.triggerGC)
                } label: {
                    Label("Initiate Memory Cleanup", systemSymbol: .memorychip)
                }
                .buttonStyle(.bordered)
                .disabled(store.state.isProcessing || !store.state.kernelIsRunning)
            }
        } header: {
            Label("Cache Operations", systemSymbol: .externaldrive)
        } footer: {
            Text("Manage DNS and Fake IP caches, and initiate memory garbage collection.")
                .foregroundStyle(.secondary)
        }
    }

    private var systemInfoSection: some View {
        Section {
            LabeledContent("Memory Usage") {
                Text(store.state.memoryUsage)
                    .font(.system(.body, design: .monospaced))
            }

            LabeledContent("Traffic") {
                Text(store.state.trafficInfo)
                    .font(.system(.body, design: .monospaced))
            }

            LabeledContent("Core Version") {
                Text(store.state.version.isEmpty ? "--" : store.state.version)
                    .font(.system(.body, design: .monospaced))
            }
        } header: {
            Label("System Information", systemSymbol: .infoCircleFill)
        } footer: {
            Text("Real-time metrics from the Mihomo core.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var progressOverlay: some View {
        if store.state.isProcessing {
            ZStack {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Applying Changes")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: store.state.isProcessing)
        }
    }

    private func helperApprovalNotice(
        text: String = "Allow the helper in Privacy & Security → Developer Tools",
        ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemSymbol: .exclamationmarkTriangleFill)
                .accessibilityHidden(true)
                .foregroundStyle(.orange)
            Text(text)
                .font(.callout)
                .foregroundStyle(.orange)
        }
        .padding(12)
        .background(
            Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous),
            )
    }

    private func helperApprovalActions(needsStatusRefresh: Bool = false) -> some View {
        HStack(spacing: 12) {
            Button {
                store.send(.openSystemSettings)
            } label: {
                Label("Open System Settings", systemSymbol: .gear)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.state.isProcessing)

            Button {
                if needsStatusRefresh {
                    store.send(.confirmBootstrap)
                }
            } label: {
                Label(
                    needsStatusRefresh ? "Refresh Status" : "Check Status", systemSymbol: .arrowClockwise,
                    )
            }
            .buttonStyle(.bordered)
            .disabled(store.state.isProcessing)
        }
    }

    private func portInfoRow(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.callout)
            }

            Text(detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
