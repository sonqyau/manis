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

        setupSyntaxHighlighting(for: textView, language: language)

        return textView
    }

    public func updateNSView(_ nsView: STTextView, context _: Context) {
        if nsView.text != text {
            nsView.text = text
            highlightSyntax(in: nsView, language: language)
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

        init(_ parent: TextKit2Extension) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? STTextView else { return }
            parent.text = textView.text ?? ""
            parent.highlightSyntax(in: textView, language: parent.language)
        }
    }

    private func setupSyntaxHighlighting(for textView: STTextView, language: TextKit2Language) {
        highlightSyntax(in: textView, language: language)
    }

    private func highlightSyntax(in textView: STTextView, language: TextKit2Language) {
        guard let text = textView.text, !text.isEmpty else { return }

        let attributedString = NSMutableAttributedString(string: text)

        let fullRange = NSRange(location: 0, length: attributedString.length)
        attributedString.addAttribute(.foregroundColor, value: theme.textColor, range: fullRange)
        attributedString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular), range: fullRange)

        switch language {
        case .log:
            highlightLogSyntax(attributedString: attributedString)
        case .yaml:
            highlightYAMLSyntax(attributedString: attributedString)
        case .json:
            highlightJSONSyntax(attributedString: attributedString)
        case .plain:
            break
        }

        textView.attributedText = attributedString
    }

    private func highlightLogSyntax(attributedString: NSMutableAttributedString) {
        let string = attributedString.string

        let logLevelPatterns = [
            "DEBUG": NSColor.gray,
            "INFO": NSColor.blue,
            "WARN": NSColor.orange,
            "WARNING": NSColor.orange,
            "ERROR": NSColor.red,
        ]

        for (level, color) in logLevelPatterns {
            let pattern = "\\b\(level)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let matches = regex.matches(in: string, range: NSRange(location: 0, length: string.count))
                for match in matches {
                    attributedString.addAttribute(.foregroundColor, value: color, range: match.range)
                }
            }
        }

        let timestampPattern = "\\d{4}-\\d{2}-\\d{2}\\s+\\d{2}:\\d{2}:\\d{2}"
        if let regex = try? NSRegularExpression(pattern: timestampPattern, options: []) {
            let matches = regex.matches(in: string, range: NSRange(location: 0, length: string.count))
            for match in matches {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: match.range)
            }
        }

        let ipPattern = "\\b\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\b"
        if let regex = try? NSRegularExpression(pattern: ipPattern, options: []) {
            let matches = regex.matches(in: string, range: NSRange(location: 0, length: string.count))
            for match in matches {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: match.range)
            }
        }
    }

    private func highlightYAMLSyntax(attributedString: NSMutableAttributedString) {
        let string = attributedString.string

        let keyPattern = "^(\\s*)[^\\s#:][^#:]*\\s*:"
        if let regex = try? NSRegularExpression(pattern: keyPattern, options: [.anchorsMatchLines]) {
            let matches = regex.matches(in: string, range: NSRange(location: 0, length: string.count))
            for match in matches {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: match.range)
            }
        }

        let commentPattern = "#.*$"
        if let regex = try? NSRegularExpression(pattern: commentPattern, options: [.anchorsMatchLines]) {
            let matches = regex.matches(in: string, range: NSRange(location: 0, length: string.count))
            for match in matches {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: match.range)
            }
        }

        let stringPattern = ":\\s*[\"']([^\"']*)[\"']"
        if let regex = try? NSRegularExpression(pattern: stringPattern, options: []) {
            let matches = regex.matches(in: string, range: NSRange(location: 0, length: string.count))
            for match in matches where match.numberOfRanges > 1 {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: match.range(at: 1))
            }
        }

        let numberPattern = ":\\s*\\d+(\\.\\d+)?"
        if let regex = try? NSRegularExpression(pattern: numberPattern, options: []) {
            let matches = regex.matches(in: string, range: NSRange(location: 0, length: string.count))
            for match in matches {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: match.range)
            }
        }

        let boolPattern = ":\\s*(true|false|yes|no|on|off)"
        if let regex = try? NSRegularExpression(pattern: boolPattern, options: [.caseInsensitive]) {
            let matches = regex.matches(in: string, range: NSRange(location: 0, length: string.count))
            for match in matches {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemRed, range: match.range)
            }
        }
    }

    private func highlightJSONSyntax(attributedString: NSMutableAttributedString) {
        let string = attributedString.string

        let keyPattern = "\"([^\"]*)\"\\s*:"
        if let regex = try? NSRegularExpression(pattern: keyPattern, options: []) {
            let matches = regex.matches(in: string, range: NSRange(location: 0, length: string.count))
            for match in matches where match.numberOfRanges > 1 {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: match.range(at: 1))
            }
        }

        let stringPattern = ":\\s*\"([^\"]*)\""
        if let regex = try? NSRegularExpression(pattern: stringPattern, options: []) {
            let matches = regex.matches(in: string, range: NSRange(location: 0, length: string.count))
            for match in matches where match.numberOfRanges > 1 {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: match.range(at: 1))
            }
        }

        let numberPattern = ":\\s*(-?\\d+(\\.\\d+)?)"
        if let regex = try? NSRegularExpression(pattern: numberPattern, options: []) {
            let matches = regex.matches(in: string, range: NSRange(location: 0, length: string.count))
            for match in matches {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: match.range)
            }
        }

        let valuePattern = ":\\s*(true|false|null)"
        if let regex = try? NSRegularExpression(pattern: valuePattern, options: [.caseInsensitive]) {
            let matches = regex.matches(in: string, range: NSRange(location: 0, length: string.count))
            for match in matches {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemRed, range: match.range)
            }
        }
    }
}
