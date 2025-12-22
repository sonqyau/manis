import AppKit
import Foundation
import STTextView

@MainActor
public class DiagnosticPlugin: STPlugin {
    public struct Diagnostic {
        public let range: NSRange
        public let type: DiagnosticFragment.DiagnosticType
        public let message: String

        public init(range: NSRange, type: DiagnosticFragment.DiagnosticType, message: String) {
            self.range = range
            self.type = type
            self.message = message
        }
    }

    private weak var textView: STTextView?
    private var diagnostics: [Diagnostic] = []

    public init() {}

    public func setUp(context: any Context) {
        self.textView = context.textView

        if let layoutManager = context.textView.textLayoutManager as? TextLayout {
            layoutManager.customDelegate = self
        }
    }

    public func tearDown() {
        textView = nil
        diagnostics.removeAll()
    }

    public func addDiagnostic(_ diagnostic: Diagnostic) {
        diagnostics.append(diagnostic)
        invalidateLayout(for: diagnostic.range)
    }

    public func removeDiagnostics(in range: NSRange) {
        diagnostics.removeAll { diagnostic in
            NSIntersectionRange(diagnostic.range, range).length > 0
        }
        invalidateLayout(for: range)
    }

    public func clearDiagnostics() {
        let allRanges = diagnostics.map(\.range)
        diagnostics.removeAll()

        for range in allRanges {
            invalidateLayout(for: range)
        }
    }

    public func diagnostic(at location: Int) -> Diagnostic? {
        diagnostics.first { diagnostic in
            NSLocationInRange(location, diagnostic.range)
        }
    }

    private func invalidateLayout(for _: NSRange) {
        guard let textView else {
            return
        }

        let layoutManager = textView.textLayoutManager
        layoutManager.invalidateLayout(for: layoutManager.documentRange)
    }
}

@MainActor
extension DiagnosticPlugin: @MainActor ManisTextLayoutManagerDelegate {
    public func textLayoutManager(
        _ textLayoutManager: TextLayout,
        customLayoutFragmentFor _: NSTextLocation,
        in textElement: NSTextElement,
        ) -> NSTextLayoutFragment? {
        guard let _ = textLayoutManager.textContentManager,
              let elementRange = textElement.elementRange
        else {
            return nil
        }

        let elementDiagnostics = diagnostics.filter { diagnostic in
            diagnostic.range.location >= 0
        }

        if let diagnostic = elementDiagnostics.first {
            let fragment = DiagnosticFragment(textElement: textElement, range: elementRange)
            fragment.diagnosticType = diagnostic.type
            fragment.diagnosticMessage = diagnostic.message
            return fragment
        }

        return nil
    }
}
