import Charts
import Collections
import ComposableArchitecture
import Perception
import SFSafeSymbols
import SwiftUI

struct OverviewView: View {
    @Bindable private var bindableStore: StoreOf<OverviewFeature>

    init(store: StoreOf<OverviewFeature>) {
        _bindableStore = Bindable(wrappedValue: store)
    }

    var body: some View {
        Form {
            statsSection(summary: bindableStore.overviewSummary)
            trafficSection(history: bindableStore.trafficHistory)
            systemInfoSection(
                summary: bindableStore.overviewSummary,
                isConnected: bindableStore.isConnected,
            )
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("System Overview")
        .task { bindableStore.send(.onAppear) }
        .onDisappear { bindableStore.send(.onDisappear) }
    }

    private func statsSection(summary: OverviewFeature.State.OverviewSummary) -> some View {
        Section {
            VStack(spacing: 12) {
                OverviewMetricRow(
                    title: "Download",
                    value: summary.downloadSpeed,
                    icon: .arrowDownCircleFill,
                    tint: .blue,
                )

                OverviewMetricRow(
                    title: "Upload",
                    value: summary.uploadSpeed,
                    icon: .arrowUpCircleFill,
                    tint: .green,
                )

                OverviewMetricRow(
                    title: "Connections",
                    value: "\(summary.connectionCount)",
                    icon: .network,
                    tint: .purple,
                )

                OverviewMetricRow(
                    title: "Memory",
                    value: ByteCountFormatter.string(
                        fromByteCount: summary.memoryUsage,
                        countStyle: .memory,
                    ),
                    icon: .memorychipFill,
                    tint: .orange,
                )
            }
            .padding(.vertical, 6)
        } header: {
            Label("Performance Metrics", systemSymbol: .gaugeWithDotsNeedleBottom50percent)
        }
    }

    private func trafficSection(history: Deque<TrafficPoint>) -> some View {
        Section {
            VStack(spacing: 20) {
                trafficChart(title: "Download", history: history, keyPath: \.download, color: .blue)
                trafficChart(title: "Upload", history: history, keyPath: \.upload, color: .green)
            }
            .padding(.vertical, 6)
        } header: {
            Label("Network Traffic", systemSymbol: .chartXyaxisLine)
        }
    }

    private func systemInfoSection(
        summary: OverviewFeature.State.OverviewSummary,
        isConnected: Bool,
    ) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                EmptyView()
                    .if(!summary.version.isEmpty) { _ in
                        LabeledContent("Version") {
                            Text(summary.version)
                        }
                    }

                LabeledContent("Connection Status") {
                    Text(isConnected ? "Active" : "Inactive")
                        .if(isConnected) { $0.foregroundStyle(.green) }
                        .ifNot(isConnected) { $0.foregroundStyle(.red) }
                }
            }
            .padding(.vertical, 6)
        } header: {
            Label("System information", systemSymbol: .infoCircleFill)
        }
    }

    private func trafficChart(
        title: String,
        history: Deque<TrafficPoint>,
        keyPath: KeyPath<TrafficPoint, Double>,
        color: Color,
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            Chart(history) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value(title, point[keyPath: keyPath]),
                )
                .foregroundStyle(color.gradient)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value(title, point[keyPath: keyPath]),
                )
                .foregroundStyle(color.opacity(0.12).gradient)
                .interpolationMethod(.catmullRom)
            }
            .frame(height: 140)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
        }
    }
}

private struct OverviewMetricRow: View {
    let title: String
    let value: String
    let icon: SFSymbol
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemSymbol: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title3)
                    .contentTransition(.numericText())

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }
}
