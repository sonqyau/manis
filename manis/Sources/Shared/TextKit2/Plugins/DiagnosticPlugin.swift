import AppKit
import Foundation
import Rearrange
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
    private var pendingMutations: [RangeMutation] = []

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
        pendingMutations.removeAll()
    }

    public func addDiagnostic(_ diagnostic: Diagnostic) {
        diagnostics.append(diagnostic)
        invalidateLayout(for: diagnostic.range)
    }

    public func removeDiagnostics(in range: NSRange) {
        diagnostics.removeAll { diagnostic in
            range.intersects(diagnostic.range)
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
            diagnostic.range.contains(location)
        }
    }

    private func invalidateLayout(for _: NSRange) {
        guard let textView else {
            return
        }

        let layoutManager = textView.textLayoutManager
        layoutManager.invalidateLayout(for: layoutManager.documentRange)
    }

    public func applyTextMutation(_ mutation: RangeMutation) {
        pendingMutations.append(mutation)

        var updatedDiagnostics: [Diagnostic] = []

        for diagnostic in diagnostics {
            if let updatedRange = diagnostic.range.apply(mutation) {
                let updatedDiagnostic = Diagnostic(
                    range: updatedRange,
                    type: diagnostic.type,
                    message: diagnostic.message,
                    )
                updatedDiagnostics.append(updatedDiagnostic)
            }
        }

        diagnostics = updatedDiagnostics
        invalidateLayout(for: mutation.range)
    }

    public func diagnosticsInRange(_ range: NSRange) -> [Diagnostic] {
        diagnostics.filter { diagnostic in
            range.intersects(diagnostic.range)
        }
    }
}

@MainActor
extension DiagnosticPlugin: @MainActor ManisTextLayoutManagerDelegate {
    public func textLayoutManager(
        _ textLayoutManager: TextLayout,
        customLayoutFragmentFor _: NSTextLocation,
        in textElement: NSTextElement,
        ) -> NSTextLayoutFragment? {
        guard textLayoutManager.textContentManager != nil,
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
