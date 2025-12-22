import AppKit
import Foundation

public class HighlightFragment: NSTextLayoutFragment {
    public var isHighlighted: Bool = false
    public var highlightColor: NSColor?

    private var defaultHighlightColor: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(0.1)
    }

    private var effectiveHighlightColor: NSColor {
        highlightColor ?? defaultHighlightColor
    }

    private var highlightBounds: CGRect {
        guard isHighlighted else { return .zero }

        var bounds = layoutFragmentFrame
        bounds.origin = .zero
        return bounds
    }

    override public var renderingSurfaceBounds: CGRect {
        let originalBounds = super.renderingSurfaceBounds
        let highlight = highlightBounds

        if highlight.isNull {
            return originalBounds
        }

        return originalBounds.union(highlight)
    }

    override public func draw(at renderingOrigin: CGPoint, in ctx: CGContext) {
        if isHighlighted {
            drawHighlight(at: renderingOrigin, in: ctx)
        }

        super.draw(at: renderingOrigin, in: ctx)
    }

    private func drawHighlight(at _: CGPoint, in ctx: CGContext) {
        ctx.saveGState()

        let highlightRect = highlightBounds
        ctx.setFillColor(effectiveHighlightColor.cgColor)
        ctx.fill(highlightRect)

        ctx.restoreGState()
    }
}
