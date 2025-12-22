import AppKit
import Foundation
import STTextView

public class TextLayout: STTextLayoutManager, NSTextLayoutManagerDelegate {
    public var layoutFragmentFactory: ((NSTextElement, NSTextRange) -> NSTextLayoutFragment)?

    public weak var customDelegate: ManisTextLayoutManagerDelegate?

    override public init() {
        super.init()
        self.delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.delegate = self
    }

    public func textLayoutManager(
        _: NSTextLayoutManager,
        textLayoutFragmentFor location: NSTextLocation,
        in textElement: NSTextElement,
        ) -> NSTextLayoutFragment {
        if let customDelegate,
           let customFragment = customDelegate.textLayoutManager(
            self,
            customLayoutFragmentFor: location,
            in: textElement,
            ) {
            return customFragment
        }

        if let factory = layoutFragmentFactory,
           let elementRange = textElement.elementRange {
            return factory(textElement, elementRange)
        }

        return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange!)
    }
}

public protocol ManisTextLayoutManagerDelegate: AnyObject {
    func textLayoutManager(
        _ textLayoutManager: TextLayout,
        customLayoutFragmentFor location: NSTextLocation,
        in textElement: NSTextElement,
        ) -> NSTextLayoutFragment?
}
