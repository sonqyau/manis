import STTextView
import Foundation
import AppKit
import Cocoa

@MainActor
public class HighlightPlugin: STPlugin {
    
    private weak var textView: STTextView?
    private let language: TextKit2Language
    private let theme: TextKit2Theme
    private let fontSize: CGFloat
    
    private var highlightedRanges: Set<NSRange> = []
    private var lastHighlightedText: String = ""
    
    public init(language: TextKit2Language, theme: TextKit2Theme, fontSize: CGFloat = 12) {
        self.language = language
        self.theme = theme
        self.fontSize = fontSize
    }
    
    public func setUp(context: any Context) {
        self.textView = context.textView
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange),
            name: NSText.didChangeNotification,
            object: context.textView
        )
        
        highlightVisibleRange()
    }
    
    public func tearDown() {
        NotificationCenter.default.removeObserver(self)
        textView = nil
        highlightedRanges.removeAll()
    }
    
    @objc private func textDidChange(_ notification: Notification) {
        highlightChangedRanges()
    }
    
    private func highlightVisibleRange() {
        guard let textView = textView,
              let text = textView.text else {
            return
        }
        
        let attributedText = applySyntaxHighlighting(to: NSAttributedString(string: text))
        textView.attributedText = attributedText
    }
    
    private func highlightChangedRanges() {
        guard let textView = textView,
              let text = textView.text else {
            return
        }
        
        if text != lastHighlightedText {
            lastHighlightedText = text
            highlightedRanges.removeAll()
            highlightVisibleRange()
        }
    }
    
    private func applySyntaxHighlighting(to attributedString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        let fullRange = NSRange(location: 0, length: mutableString.length)
        
        mutableString.addAttribute(.foregroundColor, value: theme.textColor, range: fullRange)
        
        mutableString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular), range: fullRange)
        
        switch language {
        case .log:
            highlightLogSyntax(in: mutableString)
        case .yaml:
            highlightYAMLSyntax(in: mutableString)
        case .json:
            highlightJSONSyntax(in: mutableString)
        case .plain:
            break
        }
        
        return mutableString
    }
}
    private func highlightLogSyntax(in attributedString: NSMutableAttributedString) {
        let logLevelPatterns = [
            "DEBUG": NSColor.systemGray,
            "INFO": NSColor.systemBlue,
            "WARN": NSColor.systemOrange,
            "WARNING": NSColor.systemOrange,
            "ERROR": NSColor.systemRed,
        ]
        
        for (level, color) in logLevelPatterns {
            highlightPattern("\\b\(level)\\b", with: color, in: attributedString, options: [.caseInsensitive])
        }
        
        highlightPattern("\\d{4}-\\d{2}-\\d{2}\\s+\\d{2}:\\d{2}:\\d{2}", with: NSColor.systemGreen, in: attributedString)
        
        highlightPattern("\\b\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\b", with: NSColor.systemPurple, in: attributedString)
    }
    
    private func highlightYAMLSyntax(in attributedString: NSMutableAttributedString) {
        highlightPattern("^(\\s*)[^\\s#:][^#:]*\\s*:", with: NSColor.systemBlue, in: attributedString, options: [.anchorsMatchLines])
        
        highlightPattern("#.*$", with: NSColor.systemGreen, in: attributedString, options: [.anchorsMatchLines])
        
        highlightPattern(":\\s*[\"']([^\"']*)[\"']", with: NSColor.systemOrange, in: attributedString, captureGroup: 1)
        
        highlightPattern(":\\s*\\d+(\\.\\d+)?", with: NSColor.systemPurple, in: attributedString)
        
        highlightPattern(":\\s*(true|false|yes|no|on|off)", with: NSColor.systemRed, in: attributedString, options: [.caseInsensitive])
    }
    
    private func highlightJSONSyntax(in attributedString: NSMutableAttributedString) {
        highlightPattern("\"([^\"]*)\"\\s*:", with: NSColor.systemBlue, in: attributedString, captureGroup: 1)
        
        highlightPattern(":\\s*\"([^\"]*)\"", with: NSColor.systemOrange, in: attributedString, captureGroup: 1)
        
        highlightPattern(":\\s*(-?\\d+(\\.\\d+)?)", with: NSColor.systemPurple, in: attributedString)
        
        highlightPattern(":\\s*(true|false|null)", with: NSColor.systemRed, in: attributedString, options: [.caseInsensitive])
    }
    
    private func highlightPattern(
        _ pattern: String,
        with color: NSColor,
        in attributedString: NSMutableAttributedString,
        options: NSRegularExpression.Options = [],
        captureGroup: Int = 0
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return
        }
        
        let string = attributedString.string
        let matches = regex.matches(in: string, range: NSRange(location: 0, length: string.count))
        
        for match in matches {
            let range = captureGroup > 0 && match.numberOfRanges > captureGroup
                ? match.range(at: captureGroup)
                : match.range
            
            if range.location != NSNotFound {
                attributedString.addAttribute(.foregroundColor, value: color, range: range)
            }
        }
    }