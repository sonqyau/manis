import AppKit
import Cocoa
import Foundation
import STTextView
import SwiftUI

public enum TextKit2Bridge {
    public enum LayoutFragmentFactory {
        public static func diagnostic(
            for textElement: NSTextElement,
            range: NSTextRange,
            type: DiagnosticFragment.DiagnosticType,
            message: String? = nil,
        ) -> NSTextLayoutFragment {
            let fragment = DiagnosticFragment(textElement: textElement, range: range)
            fragment.diagnosticType = type
            fragment.diagnosticMessage = message
            return fragment
        }

        public static func codeBlock(
            for textElement: NSTextElement,
            range: NSTextRange,
            language: String? = nil,
        ) -> NSTextLayoutFragment {
            let fragment = CodeBlockFragment(textElement: textElement, range: range)
            fragment.isCodeBlock = true
            fragment.codeBlockLanguage = language
            return fragment
        }

        public static func highlight(
            for textElement: NSTextElement,
            range: NSTextRange,
            color: NSColor? = nil,
        ) -> NSTextLayoutFragment {
            let fragment = HighlightFragment(textElement: textElement, range: range)
            fragment.isHighlighted = true
            fragment.highlightColor = color
            return fragment
        }
    }

    public enum PluginFactory {
        @MainActor
        public static func syntaxHighlighting(
            language: TextKit2Language,
            theme: TextKit2Theme,
            fontSize: CGFloat = 12,
        ) -> HighlightPlugin {
            HighlightPlugin(language: language, theme: theme, fontSize: fontSize)
        }

        @MainActor
        public static func diagnostic() -> DiagnosticPlugin {
            DiagnosticPlugin()
        }
    }

    public enum Utilities {
        public static func textRange(
            from nsRange: NSRange,
            in textContentManager: NSTextContentManager,
        ) -> NSTextRange? {
            NSTextRange(nsRange, in: textContentManager)
        }

        public static func nsRange(
            from textRange: NSTextRange,
            in textContentManager: NSTextContentManager,
        ) -> NSRange {
            NSRange(textRange, in: textContentManager)
        }

        public static func visibleRange(
            from layoutManager: NSTextLayoutManager,
        ) -> NSTextRange? {
            layoutManager.textViewportLayoutController.viewportRange
        }

        public static func enumerateVisibleFragments(
            in layoutManager: NSTextLayoutManager,
            using block: (NSTextLayoutFragment) -> Bool,
        ) {
            guard let viewportRange = layoutManager.textViewportLayoutController.viewportRange else {
                return
            }

            layoutManager.enumerateTextLayoutFragments(
                from: viewportRange.location,
                options: .ensuresLayout,
                using: block,
            )
        }
    }
}

public extension TextKit2Extension {
    static func withDiagnostics(
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
        return textExtension
    }

    static func withPlugins(
        text: Binding<String>,
        isEditable: Bool = true,
        language: TextKit2Language = .plain,
        fontSize: CGFloat = 12,
        theme: TextKit2Theme = .default,
        plugins: [any STPlugin],
    ) -> TextKit2Extension {
        var textExtension = TextKit2Extension(
            text: text,
            isEditable: isEditable,
            language: language,
            fontSize: fontSize,
            theme: theme,
        )
        textExtension.plugins = plugins
        return textExtension
    }

    static func withCustomFragments(
        text: Binding<String>,
        isEditable: Bool = true,
        language: TextKit2Language = .plain,
        fontSize: CGFloat = 12,
        theme: TextKit2Theme = .default,
        fragmentFactory: @escaping (NSTextElement, NSTextRange) -> NSTextLayoutFragment,
    ) -> TextKit2Extension {
        var textExtension = TextKit2Extension(
            text: text,
            isEditable: isEditable,
            language: language,
            fontSize: fontSize,
            theme: theme,
        )
        textExtension.layoutFragmentFactory = fragmentFactory
        return textExtension
    }
}
