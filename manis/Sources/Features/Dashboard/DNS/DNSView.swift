import ComposableArchitecture
import Perception
import SwiftUI

struct DNSView: View {
    @Bindable private var bindableStore: StoreOf<DNSFeature>
    @FocusState private var isDomainFocused: Bool

    init(store: StoreOf<DNSFeature>) {
        _bindableStore = Bindable(wrappedValue: store)
    }

    private var domainBinding: Binding<String> {
        Binding(
            get: { bindableStore.domain },
            set: { bindableStore.send(.updateDomain($0)) },
        )
    }

    var body: some View {
        Form {
            querySection

            if let result = bindableStore.queryResult {
                resultsSection(result: result)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("DNS Lookup")
        .alert(
            Binding<AlertState<DNSFeature.AlertAction>?>(
                get: { bindableStore.alert },
                set: { _ in },
            ),
        ) { action in
            if let action {
                bindableStore.send(.alert(action))
            }
        }
    }

    private var querySection: some View {
        Section {
            VStack(spacing: 16) {
                TextField("domain.example", text: domainBinding)
                    .textFieldStyle(.roundedBorder)
                    .focused($isDomainFocused)

                Picker(
                    "Record Type",
                    selection: Binding(
                        get: { bindableStore.recordType },
                        set: { bindableStore.send(.selectRecordType($0)) },
                    ),
                ) {
                    ForEach(bindableStore.recordTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    bindableStore.send(.performQuery)
                } label: {
                    HStack {
                        if bindableStore.isQuerying {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Start DNS lookup", systemImage: "magnifyingglass")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(bindableStore.domain.isEmpty || bindableStore.isQuerying)

                Button {
                    bindableStore.send(.flushDNSCache)
                } label: {
                    HStack {
                        if bindableStore.isFlushingCache {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Clear DNS Cache", systemImage: "trash")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(bindableStore.isFlushingCache)
            }
            .padding(.vertical, 4)
        } header: {
            Label("DNS Lookup", systemImage: "globe")
        }
    }

    private func resultsSection(result: DNSQueryResponse) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                LabeledContent("Response Status") {
                    Text("\(result.status)")
                        .font(.callout)
                }

                if !result.question.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Question section")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(result.question.indices, id: \.self) { index in
                            let question = result.question[index]
                            VStack(alignment: .leading, spacing: 4) {
                                Text(question.name)
                                    .font(.system(.body, design: .monospaced))
                                Text("Record type: \(question.qtype)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                let answers = result.answer
                if !answers.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Answer section")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(answers.indices, id: \.self) { index in
                            DNSAnswerCard(answer: answers[index])
                        }
                    }
                } else {
                    Text("No resource records found")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Label("Lookup Results", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        }
    }
}

private struct DNSAnswerCard: View {
    let answer: DNSQueryResponse.DNSAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(answer.name)
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Text("TTL: \(answer.ttl)s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(answer.data)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}
