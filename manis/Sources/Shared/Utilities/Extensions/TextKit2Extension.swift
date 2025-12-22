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

        init(_ parent: TextKit2Extension) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? STTextView else { return }
            parent.text = textView.text ?? ""
        }

        public func addDiagnostic(range: NSRange, type: DiagnosticFragment.DiagnosticType, message: String) {
            let diagnostic = DiagnosticPlugin.Diagnostic(range: range, type: type, message: message)
            diagnosticPlugin?.addDiagnostic(diagnostic)
        }

        public func clearDiagnostics() {
            diagnosticPlugin?.clearDiagnostics()
        }
    }
}
