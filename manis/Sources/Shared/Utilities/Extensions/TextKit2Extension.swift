import Rearrange
import STTextView
import SwiftUI
import SwiftUIIntrospect

public enum TextKit2Language {
    case plain
    case yaml
    case json
    case log
}

public enum TextKit2Theme {
    case `default`
    case dark
    case light

    var textColor: NSColor {
        switch self {
        case .default: .textColor
        case .dark: .white
        case .light: .black
        }
    }

    var backgroundColor: NSColor {
        switch self {
        case .default: .textBackgroundColor
        case .dark: NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        case .light: .white
        }
    }
}

public struct TextKit2Extension: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let language: TextKit2Language
    var fontSize: CGFloat = 12
    var theme: TextKit2Theme = .default

    var plugins: [any STPlugin] = []

    var layoutFragmentFactory: ((NSTextElement, NSTextRange) -> NSTextLayoutFragment)?

    var enableDiagnostics: Bool = false
    var enableAdvancedTextProcessing: Bool = false

    public func makeNSView(context: Context) -> STTextView {
        let textView = STTextView()
        textView.textDelegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true

        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        textView.backgroundColor = theme.backgroundColor
        textView.textColor = theme.textColor

        textView.showsLineNumbers = true

        textView.textContainer.lineFragmentPadding = 8

        let syntaxPlugin = HighlightPlugin(
            language: language,
            theme: theme,
            fontSize: fontSize,
        )
        textView.addPlugin(syntaxPlugin)

        if enableDiagnostics {
            let diagnosticPlugin = DiagnosticPlugin()
            textView.addPlugin(diagnosticPlugin)
            context.coordinator.diagnosticPlugin = diagnosticPlugin
        }

        for plugin in plugins {
            textView.addPlugin(plugin)
        }

        if enableAdvancedTextProcessing {
            context.coordinator.setupTextProcessing()
        }

        return textView
    }

    public func updateNSView(_ nsView: STTextView, context _: Context) {
        if nsView.text != text {
            nsView.text = text
        }

        nsView.backgroundColor = theme.backgroundColor
        nsView.textColor = theme.textColor
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    public class Coordinator: NSObject, STTextViewDelegate {
        var parent: TextKit2Extension

        weak var diagnosticPlugin: DiagnosticPlugin?
        var textEditingCoordinator: TextCoordinator?
        private var mutationTracker = TextMutationTracker()

        init(_ parent: TextKit2Extension) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? STTextView else { return }
            let newText = textView.text ?? ""
            
            if parent.text != newText {
                trackTextMutation(from: parent.text, to: newText)
                parent.text = newText
                textEditingCoordinator?.text = newText
            }
        }

        public func addDiagnostic(range: NSRange, type: DiagnosticFragment.DiagnosticType, message: String) {
            let clampedRange = range.clamped(to: parent.text.count)
            let diagnostic = DiagnosticPlugin.Diagnostic(range: clampedRange, type: type, message: message)
            diagnosticPlugin?.addDiagnostic(diagnostic)
        }

        public func clearDiagnostics() {
            diagnosticPlugin?.clearDiagnostics()
        }

        func setupTextProcessing() {
            textEditingCoordinator = TextCoordinator()
            textEditingCoordinator?.text = parent.text
        }

        private func trackTextMutation(from oldText: String, to newText: String) {
            guard parent.enableAdvancedTextProcessing else { return }
            
            let oldLength = oldText.count
            let newLength = newText.count
            let delta = newLength - oldLength
            
            if delta != 0 {
                let changeRange = findChangeRange(from: oldText, to: newText)
                let mutation = RangeMutation(range: changeRange, delta: delta)
                mutationTracker.addMutation(mutation)
                
                diagnosticPlugin?.applyTextMutation(mutation)
            }
        }

        private func findChangeRange(from oldText: String, to newText: String) -> NSRange {
            let commonPrefix = oldText.commonPrefix(with: newText)
            let prefixLength = commonPrefix.count
            
            let oldSuffix = String(oldText.dropFirst(prefixLength))
            let newSuffix = String(newText.dropFirst(prefixLength))
            
            let commonSuffix = String(oldSuffix.reversed()).commonPrefix(with: String(newSuffix.reversed()))
            let suffixLength = commonSuffix.count
            
            let changeLength = oldText.count - prefixLength - suffixLength
            
            return NSRange(location: prefixLength, length: max(0, changeLength))
        }

        public func searchText(_ query: String) -> [TextComposer.SearchResult] {
            TextComposer.findAll(query, in: parent.text)
        }

        public func replaceText(_ searchText: String, with replacement: String) -> Bool {
            let (newText, operations) = TextComposer.replaceAll(searchText, with: replacement, in: parent.text)
            
            if !operations.isEmpty {
                parent.text = newText
                
                for operation in operations {
                    mutationTracker.addMutation(operation.mutation)
                    diagnosticPlugin?.applyTextMutation(operation.mutation)
                }
                
                return true
            }
            
            return false
        }

        public func insertText(_ text: String, at location: Int) -> Bool {
            let clampedLocation = max(0, min(location, parent.text.count))
            let (newText, mutation) = TextComposer.insertText(text, at: clampedLocation, in: parent.text)
            
            parent.text = newText
            mutationTracker.addMutation(mutation)
            diagnosticPlugin?.applyTextMutation(mutation)
            
            return true
        }

        public func deleteText(in range: NSRange) -> Bool {
            let clampedRange = range.clamped(to: parent.text.count)
            let (newText, mutation) = TextComposer.deleteText(in: clampedRange, from: parent.text)
            
            parent.text = newText
            mutationTracker.addMutation(mutation)
            diagnosticPlugin?.applyTextMutation(mutation)
            
            return true
        }
    }
}

public extension TextKit2Extension {
    static func withAdvancedProcessing(
        text: Binding<String>,
        isEditable: Bool = true,
        language: TextKit2Language = .plain,
        fontSize: CGFloat = 12,
        theme: TextKit2Theme = .default,
    ) -> TextKit2Extension {
        var textExtension = TextKit2Extension(
            text: text,
            isEditable: isEditable,
            language: language,
            fontSize: fontSize,
            theme: theme,
        )
        textExtension.enableDiagnostics = true
        textExtension.enableAdvancedTextProcessing = true
        return textExtension
    }

    static func enhanced(
        text: Binding<String>,
        isEditable: Bool = true,
        language: TextKit2Language = .plain,
        fontSize: CGFloat = 12,
        theme: TextKit2Theme = .default,
        plugins: [any STPlugin] = [],
    ) -> TextKit2Extension {
        var textExtension = TextKit2Extension(
            text: text,
            isEditable: isEditable,
            language: language,
            fontSize: fontSize,
            theme: theme,
        )
        textExtension.enableDiagnostics = true
        textExtension.enableAdvancedTextProcessing = true
        textExtension.plugins = plugins
        return textExtension
    }
}
