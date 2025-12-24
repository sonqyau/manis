import ComposableArchitecture
import Perception
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
                    Label("Install", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.state.isProcessing)

                Button {
                    store.send(.uninstallDaemon)
                } label: {
                    Label("Uninstall", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(store.state.isProcessing)

                Button {
                    store.send(.refreshDaemonStatus)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
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
            Label("Privileged Helper", systemImage: "lock.shield")
        } footer: {
            Text("This is required to start/stop the kernel.")
                .foregroundStyle(.secondary)
        }
    }

    private var kernelSection: some View {
        Section {
            HStack(spacing: 12) {
                Button {
                    store.send(store.state.kernelIsRunning ? .stopKernel : .startKernel)
                } label: {
                    Label(store.state.kernelIsRunning ? "Stop Kernel" : "Start Kernel", systemImage: store.state.kernelIsRunning ? "stop.circle" : "play.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.state.isProcessing)

                Button {
                    store.send(.refreshKernelStatus)
                } label: {
                    Label("Refresh Status", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(store.state.isProcessing)
            }
        } header: {
            Label("Kernel", systemImage: "cpu")
        } footer: {
            Text("The manis never talks to the privileged helper directly.")
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
                        Label("Restart Core", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.state.isPerformingSystemOperation || !store.state.kernelIsRunning)

                    Button {
                        store.send(.upgradeCore)
                    } label: {
                        Label("Upgrade Core", systemImage: "arrow.up.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.state.isPerformingSystemOperation || !store.state.kernelIsRunning)
                }

                HStack(spacing: 12) {
                    Button {
                        store.send(.upgradeUI)
                    } label: {
                        Label("Upgrade UI", systemImage: "paintbrush")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.state.isPerformingSystemOperation || !store.state.kernelIsRunning)

                    Button {
                        store.send(.upgradeGeo)
                    } label: {
                        Label("Upgrade GEO", systemImage: "globe")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.state.isPerformingSystemOperation || !store.state.kernelIsRunning)
                }

                if store.state.isPerformingSystemOperation {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Performing system operation...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
        } header: {
            Label("System Management", systemImage: "wrench.and.screwdriver")
        } footer: {
            Text("Manage core system operations. These operations require an active kernel connection.")
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
                systemManagementSection
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
            Label("Status", systemImage: "info.circle")
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
                    helperApprovalNotice(text: "Authorize Mihomo under Login Items in System Settings")
                    helperApprovalActions(needsStatusRefresh: false)
                }
        } header: {
            Label("Startup", systemImage: "power.circle")
        } footer: {
            Text("Start Manis automatically when you sign in to macOS.")
                .foregroundStyle(.secondary)
        }
    }

    private var configurationSection: some View {
        Section {
            NavigationLink {
                PersistenceView(store: persistenceStore)
            } label: {
                HStack {
                    Label("Manage Configurations", systemImage: "doc.text.fill")
                    Spacer()
                    Image(systemName: "chevron.right")
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
                    Label("Edit Local Config", systemImage: "doc.text")
                    Spacer()
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Label("Configuration", systemImage: "gear")
        } footer: {
            Text("Manage local and remote Mihomo configuration profiles, or edit the local config file directly.")
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
                    Label("GitHub Repository", systemImage: "link")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Opens in browser")
                }
            }
            .buttonStyle(.plain)
        } header: {
            Label("About", systemImage: "info.circle")
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
        text: String = "Allow the helper under Privacy & Security → Developer Tools",
        ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
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
                Label("Open System Settings", systemImage: "gear")
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.state.isProcessing)

            Button {
                if needsStatusRefresh {
                    store.send(.confirmBootstrap)
                }
            } label: {
                Label(
                    needsStatusRefresh ? "Refresh Status" : "Check Status", systemImage: "arrow.clockwise",
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
