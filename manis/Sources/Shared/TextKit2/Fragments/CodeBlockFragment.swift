import AppKit
import Cocoa
import Foundation

public class CodeBlockFragment: NSTextLayoutFragment {
    public var isCodeBlock: Bool = false
    public var codeBlockLanguage: String?

    override public var leadingPadding: CGFloat {
        isCodeBlock ? 12.0 : 0.0
    }

    override public var trailingPadding: CGFloat {
        isCodeBlock ? 12.0 : 0.0
    }

    override public var topMargin: CGFloat {
        isCodeBlock ? 8.0 : 0.0
    }

    override public var bottomMargin: CGFloat {
        isCodeBlock ? 8.0 : 0.0
    }

    private var codeBlockBounds: CGRect {
        guard isCodeBlock else { return .zero }

        var fragmentTextBounds = CGRect.null
        for lineFragment in textLineFragments {
            let lineFragmentBounds = lineFragment.typographicBounds
            if fragmentTextBounds.isNull {
                fragmentTextBounds = lineFragmentBounds
            } else {
                fragmentTextBounds = fragmentTextBounds.union(lineFragmentBounds)
            }
        }

        return fragmentTextBounds.insetBy(dx: -8, dy: -4)
    }

    private var codeBlockCornerRadius: CGFloat { 6.0 }

    private var codeBlockBackgroundColor: NSColor {
        NSColor.controlBackgroundColor.withAlphaComponent(0.5)
    }

    private var codeBlockBorderColor: NSColor {
        NSColor.separatorColor
    }

    override public var renderingSurfaceBounds: CGRect {
        let originalBounds = super.renderingSurfaceBounds
        let blockBounds = codeBlockBounds

        if blockBounds.isNull {
            return originalBounds
        }

        return originalBounds.union(blockBounds)
    }

    override public func draw(at renderingOrigin: CGPoint, in ctx: CGContext) {
        if isCodeBlock {
            drawCodeBlockBackground(at: renderingOrigin, in: ctx)
        }

        super.draw(at: renderingOrigin, in: ctx)
    }

    private func drawCodeBlockBackground(at _: CGPoint, in ctx: CGContext) {
        ctx.saveGState()

        let blockRect = codeBlockBounds
        let cornerRadius = min(codeBlockCornerRadius, blockRect.height / 2, blockRect.width / 2)

        let path = CGPath(
            roundedRect: blockRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil,
            )

        ctx.addPath(path)
        ctx.setFillColor(codeBlockBackgroundColor.cgColor)
        ctx.fillPath()

        ctx.addPath(path)
        ctx.setStrokeColor(codeBlockBorderColor.cgColor)
        ctx.setLineWidth(0.5)
        ctx.strokePath()

        if let language = codeBlockLanguage, !language.isEmpty {
            drawLanguageLabel(language, in: blockRect, ctx: ctx)
        }

        ctx.restoreGState()
    }

    private func drawLanguageLabel(_ language: String, in rect: CGRect, ctx _: CGContext) {
        let font = NSFont.systemFont(ofSize: 10, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        let attributedLanguage = NSAttributedString(string: language.uppercased(), attributes: attributes)
        let labelSize = attributedLanguage.size()

        let labelRect = CGRect(
            x: rect.maxX - labelSize.width - 8,
            y: rect.minY + 4,
            width: labelSize.width,
            height: labelSize.height,
            )

        attributedLanguage.draw(in: labelRect)
    }
}
