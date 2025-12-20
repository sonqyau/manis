import ComposableArchitecture
import Perception
import STTextView
import SwiftUI
import SwiftUIIntrospect

struct LogsTextView: View {
    let store: StoreOf<LogsFeature>
    @Bindable private var bindableStore: StoreOf<LogsFeature>
    @FocusState private var isSearchFocused: Bool
    @State private var showAdvancedView = false

    private let logLevels = ["debug", "info", "warning", "error"]

    init(store: StoreOf<LogsFeature>) {
        self.store = store
        _bindableStore = Bindable(wrappedValue: store)
    }

    private var levelBinding: Binding<String> {
        Binding(
            get: { bindableStore.selectedLevel },
            set: { bindableStore.send(.selectLevel($0)) },
            )
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { bindableStore.searchText },
            set: { bindableStore.send(.updateSearch($0)) },
            )
    }

    private var autoScrollBinding: Binding<Bool> {
        Binding(
            get: { bindableStore.autoScroll },
            set: { bindableStore.send(.toggleAutoScroll($0)) },
            )
    }

    private var formattedLogText: String {
        let logs = bindableStore.filteredLogs.isEmpty ? bindableStore.logs : bindableStore.filteredLogs
        return logs.map { log in
            let level = log.type.uppercased()
            return "[\(level)] \(log.payload)"
        }
        .joined(separator: "\n")
    }

    var body: some View {
        Form {
            controlsSection
            logViewerSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("System logs")
        .task { bindableStore.send(.onAppear) }
        .onDisappear { bindableStore.send(.onDisappear) }
        .alert(
            Binding<AlertState<LogsFeature.AlertAction>?>(
                get: { bindableStore.alert },
                set: { _ in },
                ),
            ) { action in
            if let action {
                bindableStore.send(.alert(action))
            }
        }
    }

    private var controlsSection: some View {
        Section {
            VStack(spacing: 16) {
                Picker("Log Level", selection: levelBinding) {
                    ForEach(logLevels, id: \.self) { level in
                        Text(level.capitalized).tag(level)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 12) {
                    TextField("Filter log entries", text: searchBinding)
                        .textFieldStyle(.roundedBorder)
                        .focused($isSearchFocused)

                    if !bindableStore.searchText.isEmpty {
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

                Toggle("Auto-scroll", isOn: autoScrollBinding)
                    .toggleStyle(.switch)

                HStack {
                    Button {
                        bindableStore.send(.clearLogs)
                    } label: {
                        Label("Clear log buffer", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(bindableStore.logs.isEmpty)

                    Spacer()

                    Button {
                        bindableStore.send(.toggleStreaming)
                    } label: {
                        Label(
                            bindableStore.isStreaming ? "Stop streaming" : "Start streaming",
                            systemImage: bindableStore.isStreaming ? "stop.fill" : "play.fill",
                            )
                    }
                    .buttonStyle(.borderedProminent)
                }

                Toggle("Advanced Text View", isOn: $showAdvancedView)
                    .toggleStyle(.switch)
            }
            .padding(.vertical, 6)
        } header: {
            Label("Controls", systemImage: "slider.horizontal.3")
        }
    }

    private var logViewerSection: some View {
        Section {
            if showAdvancedView {
                advancedLogViewer
            } else {
                basicLogViewer
            }
        } header: {
            HStack {
                Label("Log Entries", systemImage: "doc.text")
                Spacer()
                if bindableStore.summary.filteredLogs > 0 {
                    Text("\(bindableStore.summary.filteredLogs) of \(bindableStore.summary.totalLogs)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(bindableStore.summary.totalLogs) entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var basicLogViewer: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if bindableStore.filteredLogs.isEmpty, !bindableStore.searchText.isEmpty {
                        ContentUnavailableView {
                            Label(
                                "No matching log entries",
                                systemImage: "doc.text.magnifyingglass",
                                )
                        } description: {
                            Text("Try adjusting your search filter")
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else if bindableStore.logs.isEmpty {
                        ContentUnavailableView {
                            Label(
                                bindableStore.isStreaming ? "No log entries available" : "Log stream inactive",
                                systemImage: "doc.text.magnifyingglass",
                                )
                        } description: {
                            Text(
                                bindableStore.isStreaming
                                    ? "Waiting for incoming log messages"
                                    : "Enable streaming to receive log data",
                                )
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        ForEach(bindableStore.filteredLogs.isEmpty ? bindableStore.logs : bindableStore.filteredLogs) { log in
                            LogRow(log: log)
                                .id(log.id)
                        }
                    }
                }
                .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: bindableStore.filteredLogs.count) { _, _ in
                if bindableStore.autoScroll, let lastLog = bindableStore.filteredLogs.last ?? bindableStore.logs.last {
                    withAnimation(.smooth) {
                        proxy.scrollTo(lastLog.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(minHeight: 280)
    }

    private var advancedLogViewer: some View {
        ZStack {
            TextKit2Extension(
                text: .constant(formattedLogText),
                isEditable: false,
                language: TextKit2Language.log,
                fontSize: 11,
                theme: TextKit2Theme.default,
                )
            .frame(minHeight: 280)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if formattedLogText.isEmpty {
                ContentUnavailableView {
                    Label(
                        bindableStore.isStreaming ? "No log entries available" : "Log stream inactive",
                        systemImage: "doc.text.magnifyingglass",
                        )
                } description: {
                    Text(
                        bindableStore.isStreaming
                            ? "Waiting for incoming log messages"
                            : "Enable streaming to receive log data",
                        )
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
    }
}

private struct LogRow: View {
    let log: LogMessage

    private var logColor: Color {
        switch log.type.lowercased() {
        case "debug": .gray
        case "info": .blue
        case "warning": .orange
        case "error": .red
        default: .primary
        }
    }

    private var logIcon: String {
        switch log.type.lowercased() {
        case "debug": "ladybug.fill"
        case "info": "info.circle.fill"
        case "warning": "exclamationmark.triangle.fill"
        case "error": "xmark.octagon.fill"
        default: "circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: logIcon)
                .font(.caption)
                .foregroundStyle(logColor.gradient)
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(log.type.uppercased())
                .font(.caption)
                .foregroundStyle(logColor)
                .frame(width: 70, alignment: .leading)

            Text(log.payload)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            logColor.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 8),
            )
    }
}
