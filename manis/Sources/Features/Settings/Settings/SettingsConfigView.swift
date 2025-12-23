import Rearrange
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
    @State private var searchResults: [NSRange] = []
    @State private var currentSearchIndex = 0

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
        searchResults = findAllOccurrences(of: findText, in: text)
        currentSearchIndex = 0
        print("Found \(searchResults.count) occurrences of '\(findText)'")
    }

    private func performReplace() {
        guard !findText.isEmpty, !replaceText.isEmpty else { return }
        
        if let currentRange = getCurrentSearchResult() {
            let mutation = RangeMutation(range: currentRange, delta: replaceText.count - findText.count)
            text = replaceOccurrence(in: text, range: currentRange, with: replaceText)
            
            updateSearchResults(after: mutation)
        }
    }

    private func performReplaceAll() {
        guard !findText.isEmpty else { return }
        
        let allRanges = findAllOccurrences(of: findText, in: text)
        var mutations: [RangeMutation] = []
        
        for range in allRanges.reversed() {
            let mutation = RangeMutation(range: range, delta: replaceText.count - findText.count)
            mutations.append(mutation)
            text = replaceOccurrence(in: text, range: range, with: replaceText)
        }
        
        searchResults.removeAll()
        currentSearchIndex = 0
    }

    private func findAllOccurrences(of searchText: String, in content: String) -> [NSRange] {
        guard !searchText.isEmpty else { return [] }
        
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: content.count)
        
        while searchRange.location < content.count {
            let foundRange = (content as NSString).range(
                of: searchText,
                options: [.caseInsensitive],
                range: searchRange
            )
            
            if foundRange.location == NSNotFound {
                break
            }
            
            ranges.append(foundRange)
            searchRange = NSRange(
                location: foundRange.max,
                length: content.count - foundRange.max
            )
        }
        
        return ranges
    }

    private func replaceOccurrence(in content: String, range: NSRange, with replacement: String) -> String {
        guard let substring = content[range] else { return content }
        return content.replacingOccurrences(of: String(substring), with: replacement)
    }

    private func getCurrentSearchResult() -> NSRange? {
        guard !searchResults.isEmpty, currentSearchIndex < searchResults.count else { return nil }
        return searchResults[currentSearchIndex]
    }

    private func updateSearchResults(after mutation: RangeMutation) {
        searchResults = searchResults.compactMap { range in
            range.apply(mutation)
        }
        
        if currentSearchIndex >= searchResults.count {
            currentSearchIndex = max(0, searchResults.count - 1)
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
