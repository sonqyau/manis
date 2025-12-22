import Foundation
import QuartzCore
import AppKit
import Cocoa

public class TextFragmentLayer: CALayer {
    
    public var layoutFragment: NSTextLayoutFragment!
    public var padding: CGFloat
    public var showLayerFrames: Bool = false
    
    private let strokeWidth: CGFloat = 1.0
    
    public override class func defaultAction(forKey event: String) -> CAAction? {
        return NSNull()
    }
    
    public init(layoutFragment: NSTextLayoutFragment, padding: CGFloat) {
        self.layoutFragment = layoutFragment
        self.padding = padding
        super.init()
        
        contentsScale = 2.0
        updateGeometry()
        setNeedsDisplay()
    }
    
    public override init(layer: Any) {
        guard let fragmentLayer = layer as? TextFragmentLayer else {
            fatalError("Layer must be TextFragmentLayer")
        }
        
        self.layoutFragment = fragmentLayer.layoutFragment
        self.padding = fragmentLayer.padding
        self.showLayerFrames = fragmentLayer.showLayerFrames
        
        super.init(layer: layer)
        updateGeometry()
        setNeedsDisplay()
    }
    
    required init?(coder: NSCoder) {
        self.layoutFragment = nil
        self.padding = 0
        self.showLayerFrames = false
        super.init(coder: coder)
    }
    
    public func updateGeometry() {
        bounds = layoutFragment.renderingSurfaceBounds
        
        if showLayerFrames {
            var typographicBounds = layoutFragment.layoutFragmentFrame
            typographicBounds.origin = .zero
            bounds = bounds.union(typographicBounds)
        }
        
        anchorPoint = CGPoint(
            x: -bounds.origin.x / bounds.size.width,
            y: -bounds.origin.y / bounds.size.height
        )
        position = layoutFragment.layoutFragmentFrame.origin
        
        var newBounds = bounds
        
        newBounds.origin.x += position.x
        
        bounds = newBounds
        position.x += padding
    }
    
    public override func draw(in ctx: CGContext) {
        layoutFragment.draw(at: .zero, in: ctx)
        
        if showLayerFrames {
            drawDebugFrames(in: ctx)
        }
    }
    
    private func drawDebugFrames(in ctx: CGContext) {
        let inset = 0.5 * strokeWidth
        
        ctx.setLineWidth(strokeWidth)
        ctx.setStrokeColor(renderingSurfaceBoundsStrokeColor.cgColor)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.stroke(layoutFragment.renderingSurfaceBounds.insetBy(dx: inset, dy: inset))
        
        ctx.setStrokeColor(typographicBoundsStrokeColor.cgColor)
        ctx.setLineDash(phase: 0, lengths: [strokeWidth, strokeWidth])
        
        var typographicBounds = layoutFragment.layoutFragmentFrame
        typographicBounds.origin = .zero
        ctx.stroke(typographicBounds.insetBy(dx: inset, dy: inset))
    }
    
    private var renderingSurfaceBoundsStrokeColor: NSColor {
        return .systemOrange
    }
    
    private var typographicBoundsStrokeColor: NSColor {
        return .systemPurple
    }
}