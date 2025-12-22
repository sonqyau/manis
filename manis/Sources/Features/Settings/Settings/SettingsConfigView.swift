import STTextView
import SwiftUI
import UniformTypeIdentifiers

struct SettingsConfigView: View {
    @Binding var text: String
    @State private var isEdited = false
    @State private var showSaveDialog = false
    @State private var showOpenDialog = false
    @State private var currentFileURL: URL?
    @State private var showFindReplace = false
    @State private var findText = ""
    @State private var replaceText = ""
    @State private var isDarkTheme = false

    let fileName: String
    let fileExtension: String
    let language: TextKit2Language

    private var displayName: String {
        if let url = currentFileURL {
            return url.lastPathComponent
        }
        return fileName
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            editorView
        }
        .frame(minWidth: 600, minHeight: 400)
        .fileExporter(
            isPresented: $showSaveDialog,
            document: ConfigDocument(text: text),
            contentType: UTType(filenameExtension: fileExtension) ?? .plainText,
            defaultFilename: displayName,
        ) { result in
            switch result {
            case let .success(url):
                currentFileURL = url
                isEdited = false
            case .failure:
                break
            }
        }
        .fileImporter(
            isPresented: $showOpenDialog,
            allowedContentTypes: [UTType(filenameExtension: fileExtension) ?? .plainText],
        ) { result in
            switch result {
            case let .success(url):
                loadFile(from: url)
            case .failure:
                break
            }
        }
        .sheet(isPresented: $showFindReplace) {
            FindReplaceView(
                findText: $findText,
                replaceText: $replaceText,
                onFind: performFind,
                onReplace: performReplace,
                onReplaceAll: performReplaceAll,
            )
        }
    }

    private var toolbar: some View {
        HStack {
            Button {
                showOpenDialog = true
            } label: {
                Label("Open", systemImage: "folder")
            }
            .buttonStyle(.bordered)

            Button {
                showSaveDialog = true
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .disabled(!isEdited)

            Divider()

            Button {
                showFindReplace = true
            } label: {
                Label("Find & Replace", systemImage: "magnifyingglass")
            }
            .buttonStyle(.bordered)

            Divider()

            Toggle("Dark Theme", isOn: $isDarkTheme)
                .toggleStyle(.switch)

            Spacer()

            if isEdited {
                Text("Edited")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var editorView: some View {
        TextKit2Extension(
            text: $text,
            isEditable: true,
            language: language,
            fontSize: 12,
            theme: isDarkTheme ? TextKit2Theme.dark : TextKit2Theme.light,
        )
        .onChange(of: text) { _, _ in
            if !isEdited {
                isEdited = true
            }
        }
    }

    private func loadFile(from url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            text = content
            currentFileURL = url
            isEdited = false
        } catch {
            print("Failed to load file: \(error)")
        }
    }

    private func performFind() {
        print("Find: \(findText)")
    }

    private func performReplace() {
        if !findText.isEmpty, !replaceText.isEmpty {
            text = text.replacingOccurrences(of: findText, with: replaceText, options: .caseInsensitive)
        }
    }

    private func performReplaceAll() {
        if !findText.isEmpty {
            text = text.replacingOccurrences(of: findText, with: replaceText, options: .caseInsensitive)
        }
    }
}

struct ConfigDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return .init(regularFileWithContents: data)
    }
}

struct FindReplaceView: View {
    @Binding var findText: String
    @Binding var replaceText: String
    let onFind: () -> Void
    let onReplace: () -> Void
    let onReplaceAll: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    enum Field {
        case find, replace
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Find", text: $findText)
                        .focused($focusedField, equals: .find)

                    TextField("Replace with", text: $replaceText)
                        .focused($focusedField, equals: .replace)
                }

                Section {
                    HStack {
                        Button("Find") {
                            onFind()
                        }
                        .buttonStyle(.bordered)
                        .disabled(findText.isEmpty)

                        Button("Replace") {
                            onReplace()
                        }
                        .buttonStyle(.bordered)
                        .disabled(findText.isEmpty)

                        Button("Replace All") {
                            onReplaceAll()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(findText.isEmpty)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Find & Replace")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                focusedField = .find
            }
        }
        .frame(width: 400, height: 250)
    }
}

struct ConfigEditorWindow: View {
    @State private var configText = ""
    let fileName: String
    let fileExtension: String
    let language: TextKit2Language
    let initialContent: String?

    init(fileName: String, fileExtension: String, language: TextKit2Language, initialContent: String? = nil) {
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.language = language
        self.initialContent = initialContent
        _configText = State(initialValue: initialContent ?? "")
    }

    var body: some View {
        SettingsConfigView(
            text: $configText,
            fileName: fileName,
            fileExtension: fileExtension,
            language: language,
        )
    }
}
