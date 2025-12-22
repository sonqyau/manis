import AppKit
import Cocoa
import Foundation

public class DiagnosticFragment: NSTextLayoutFragment {
    public enum DiagnosticType {
        case none
        case error
        case warning
        case info

        var color: NSColor {
            switch self {
            case .none: .clear
            case .error: .systemRed
            case .warning: .systemOrange
            case .info: .systemBlue
            }
        }

        var symbol: String {
            switch self {
            case .none: ""
            case .error: "xmark.circle"
            case .warning: "exclamationmark.triangle"
            case .info: "info.circle"
            }
        }
    }

    public var diagnosticType: DiagnosticType = .none
    public var diagnosticMessage: String?

    override public var leadingPadding: CGFloat {
        diagnosticType != .none ? 20.0 : 0.0
    }

    override public var topMargin: CGFloat { 2.0 }
    override public var bottomMargin: CGFloat { 2.0 }

    private var diagnosticIndicatorBounds: CGRect {
        guard diagnosticType != .none else { return .zero }

        var bounds = CGRect.null
        for lineFragment in textLineFragments {
            let lineFragmentBounds = lineFragment.typographicBounds
            if bounds.isNull {
                bounds = lineFragmentBounds
            } else {
                bounds = bounds.union(lineFragmentBounds)
            }
        }

        bounds.origin.x -= 18
        bounds.size.width += 18
        return bounds
    }

    override public var renderingSurfaceBounds: CGRect {
        let originalBounds = super.renderingSurfaceBounds
        let indicatorBounds = diagnosticIndicatorBounds

        if indicatorBounds.isNull {
            return originalBounds
        }

        return originalBounds.union(indicatorBounds)
    }

    override public func draw(at renderingOrigin: CGPoint, in ctx: CGContext) {
        if diagnosticType != .none {
            drawDiagnosticIndicator(at: renderingOrigin, in: ctx)
        }

        super.draw(at: renderingOrigin, in: ctx)
    }

    private func drawDiagnosticIndicator(at renderingOrigin: CGPoint, in ctx: CGContext) {
        ctx.saveGState()

        let indicatorSize: CGFloat = 12
        let indicatorX = renderingOrigin.x - 16
        let indicatorY = renderingOrigin.y + (textLineFragments.first?.typographicBounds.midY ?? 0) - indicatorSize / 2
        let indicatorRect = CGRect(x: indicatorX, y: indicatorY, width: indicatorSize, height: indicatorSize)

        ctx.setFillColor(diagnosticType.color.cgColor)
        ctx.fillEllipse(in: indicatorRect)

        let symbol = diagnosticType.symbol
        let font = NSFont.systemFont(ofSize: 8, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]

        let attributedSymbol = NSAttributedString(string: symbol, attributes: attributes)
        let symbolSize = attributedSymbol.size()
        let symbolRect = CGRect(
            x: indicatorRect.midX - symbolSize.width / 2,
            y: indicatorRect.midY - symbolSize.height / 2,
            width: symbolSize.width,
            height: symbolSize.height,
            )

        attributedSymbol.draw(in: symbolRect)

        ctx.restoreGState()
    }
}
