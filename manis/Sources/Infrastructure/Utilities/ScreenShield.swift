//
//  Credit: https://github.com/Kyle-Ye/ScreenShieldKit (MIT)
//

import AppKit
import Foundation

private let logger = MihoLog.shared.logger(for: .core)

private final class ScreenShieldCache {
    @MainActor static let shared = ScreenShieldCache()
    private var selectorCache: [String: Selector] = [:]
    private var methodCache: [String: Bool] = [:]
    private let cacheQueue = DispatchQueue(
        label: "screenshield.cache",
        qos: .userInteractive,
        attributes: .concurrent,
    )

    func selector(for base64: String) -> Selector? {
        cacheQueue.sync {
            if let cached = selectorCache[base64] { return cached }
            guard let data = Data(base64Encoded: base64),
                  let string = String(data: data, encoding: .utf8) else { return nil }
            let selector = NSSelectorFromString(string)
            selectorCache[base64] = selector
            return selector
        }
    }

    func responds(_ target: AnyObject, to selector: Selector) -> Bool {
        let key = "\(ObjectIdentifier(target)).\(selector)"
        return cacheQueue.sync {
            if let cached = methodCache[key] { return cached }
            let responds = target.responds(to: selector)
            methodCache[key] = responds
            return responds
        }
    }
}

private extension CALayer {
    @inline(__always)
    func setValueUnsafe(_ value: AnyObject, forKey key: String) {
        let selector = NSSelectorFromString("setValue:forKey:")
        if let method = class_getInstanceMethod(type(of: self), selector) {
            let imp = method_getImplementation(method)
            typealias Function = @convention(c) (AnyObject, Selector, AnyObject, String) -> Void
            let function = unsafeBitCast(imp, to: Function.self)
            function(self, selector, value, key)
        }
    }
}

extension CALayer {
    @MainActor @discardableResult
    @inline(__always)
    public func hideFromCapture(hide: Bool = true) -> Bool {
        var success: UInt8 = 0

        if applyDisableUpdateMask(hide: hide) {
            success |= 1
            logger.debug("Applied disableUpdateMask protection: \(hide)")
        }

        if applyDisplayCompositingProtection(hide: hide) {
            success |= 2
            logger.debug("Applied display compositing protection: \(hide)")
        }

        if applySecureContentFlag(hide: hide) {
            success |= 4
            logger.debug("Applied secure content flag: \(hide)")
        }

        if success == 0 {
            logger.warning("Failed to apply any screen capture protection methods")
        }

        return success != 0
    }

    @MainActor @inline(__always)
    private func applyDisableUpdateMask(hide: Bool) -> Bool {
        let propertyBase64 = "ZGlzYWJsZVVwZGF0ZU1hc2s="

        guard let selector = ScreenShieldCache.shared.selector(for: propertyBase64),
              ScreenShieldCache.shared.responds(self, to: selector)
        else {
            return false
        }

        let value = hide ? ((1 << 1) | (1 << 4)) : 0
        setValueUnsafe(NSNumber(value: value), forKey: "disableUpdateMask")
        return true
    }

    @MainActor @inline(__always)
    private func applyDisplayCompositingProtection(hide: Bool) -> Bool {
        let propertyBase64 = "YWxsb3dzRGlzcGxheUNvbXBvc2l0aW5n"

        guard let selector = ScreenShieldCache.shared.selector(for: propertyBase64),
              ScreenShieldCache.shared.responds(self, to: selector)
        else {
            return false
        }

        setValueUnsafe(NSNumber(value: !hide), forKey: "allowsDisplayCompositing")
        return true
    }

    @MainActor @inline(__always)
    private func applySecureContentFlag(hide: Bool) -> Bool {
        let propertyBase64 = "c2VjdXJlQ29udGVudA=="

        guard let selector = ScreenShieldCache.shared.selector(for: propertyBase64),
              ScreenShieldCache.shared.responds(self, to: selector)
        else {
            return false
        }

        setValueUnsafe(NSNumber(value: hide), forKey: "secureContent")
        return true
    }
}

public extension NSView {
    @discardableResult
    @inline(__always)
    func hideFromCapture(hide: Bool = true) -> Bool {
        guard !(self is NSSecureTextField) else {
            logger.info("NSSecureTextField already has built-in capture protection")
            return true
        }

        if layer == nil {
            wantsLayer = true
        }

        guard let layer else {
            logger.error("Failed to create backing layer for NSView")
            return false
        }

        return layer.hideFromCapture(hide: hide)
    }

    @inline(__always)
    func createSecureOverlay() -> NSView? {
        let secureField = NSSecureTextField()
        secureField.isBordered = false
        secureField.isEditable = false
        secureField.isSelectable = false
        secureField.backgroundColor = .clear
        secureField.focusRingType = .none
        secureField.stringValue = ""

        let container = NSView()
        container.wantsLayer = true
        container.addSubview(secureField)

        secureField.translatesAutoresizingMaskIntoConstraints = false
        let constraints = [
            secureField.topAnchor.constraint(equalTo: container.topAnchor),
            secureField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            secureField.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            secureField.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ]
        NSLayoutConstraint.activate(constraints)

        logger.debug("Created secure overlay using NSSecureTextField")
        return container
    }

    @discardableResult
    @inline(__always)
    func applyHybridProtection(hide: Bool = true) -> NSView? {
        _ = hideFromCapture(hide: hide)

        guard hide, let overlay = createSecureOverlay() else { return nil }

        addSubview(overlay)
        overlay.frame = bounds
        overlay.autoresizingMask = [.width, .height]
        logger.info("Applied hybrid protection (layer + overlay)")
        return overlay
    }
}

public extension NSWindow {
    @discardableResult
    @inline(__always)
    func hideFromCapture(hide: Bool = true) -> Bool {
        guard let contentView else {
            logger.error("Window has no content view")
            return false
        }
        return contentView.hideFromCapture(hide: hide)
    }

    @discardableResult
    @inline(__always)
    func applyHybridProtection(hide: Bool = true) -> NSView? {
        guard let contentView else {
            logger.error("Window has no content view")
            return nil
        }
        return contentView.applyHybridProtection(hide: hide)
    }
}

public extension NSView {
    @inline(__always)
    func protectSubviewsWithTags(_ tags: [Int]) {
        for tag in tags {
            if let subview = viewWithTag(tag) {
                subview.hideFromCapture()
                logger.debug("Protected subview with tag: \(tag)")
            }
        }
    }

    @inline(__always)
    func protectSubviews<T: NSView>(ofType type: T.Type) {
        for subview in subviews {
            if subview is T {
                subview.hideFromCapture()
                logger.debug("Protected subview of type: \(String(describing: type))")
            }
            subview.protectSubviews(ofType: type)
        }
    }
}
