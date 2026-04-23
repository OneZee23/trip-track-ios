import UIKit
import OSLog

/// Centralized logger for every surface involved in the nav-bar flash bug.
/// All events go through the same subsystem/category so Xcode Console
/// filter "subsystem:com.triptrack category:navflash" shows a single
/// interleaved timeline — view lifecycle, back-button taps, nav controller
/// events, and frame-by-frame bar state all in order.
enum NavFlashDebug {
    static let log = Logger(subsystem: "com.triptrack", category: "navflash")

    /// Short, stable identifier for any object — last 4 hex digits of its
    /// pointer. Keeps log lines scannable compared to a full address.
    static func tag(_ obj: AnyObject) -> String {
        let p = UInt(bitPattern: ObjectIdentifier(obj).hashValue)
        return String(format: "%04x", p & 0xffff)
    }

    /// Describes a UIViewController in one line: class + tag + extra
    /// context (e.g. title). Safe to call from anywhere.
    static func describe(_ vc: UIViewController?) -> String {
        guard let vc else { return "nil" }
        let cls = String(describing: type(of: vc))
        return "\(cls)#\(tag(vc))"
    }

    /// Walk up the responder chain and report ancestor view controllers —
    /// shows you exactly which NavigationStack/sheet contains the caller.
    static func responderChain(from view: UIView?) -> String {
        guard let view else { return "∅" }
        var r: UIResponder? = view
        var parts: [String] = []
        while let cur = r {
            if let vc = cur as? UIViewController {
                parts.append(describe(vc))
            }
            r = cur.next
        }
        return parts.joined(separator: " → ")
    }
}

/// Samples a UINavigationBar's visual state every frame via CADisplayLink
/// and emits a log line ONLY when something changes. Ordinary KVO on
/// `alpha`/`isHidden` misses flashes because UIKit animates via CAAnimation
/// on the presentation layer — the model value never changes, but the
/// presentation layer does. This watcher reads `layer.presentation()` so
/// we see what's actually on screen at each frame.
final class NavBarFrameWatcher {
    private weak var bar: UINavigationBar?
    private weak var navController: UINavigationController?
    private var link: CADisplayLink?
    private var lastAlpha: Float = .nan
    private var lastY: CGFloat = .nan
    private var lastH: CGFloat = .nan
    private var lastAnimCount: Int = -1
    private let ownerTag: String

    init(bar: UINavigationBar, navController: UINavigationController, ownerTag: String) {
        self.bar = bar
        self.navController = navController
        self.ownerTag = ownerTag
    }

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
        NavFlashDebug.log.debug("watcher[\(self.ownerTag, privacy: .public)].start")
    }

    func stop() {
        link?.invalidate()
        link = nil
        NavFlashDebug.log.debug("watcher[\(self.ownerTag, privacy: .public)].stop")
    }

    @objc private func tick() {
        guard let bar, let nav = navController else { stop(); return }
        let pres = bar.layer.presentation()
        let alpha = pres?.opacity ?? Float(bar.layer.opacity)
        let frame = pres?.frame ?? bar.frame
        let y = frame.origin.y
        let h = frame.size.height
        let animCount = bar.layer.animationKeys()?.count ?? 0

        let alphaChanged = abs(alpha - lastAlpha) > 0.01 || lastAlpha.isNaN
        let yChanged = abs(y - lastY) > 0.5 || lastY.isNaN
        let hChanged = abs(h - lastH) > 0.5 || lastH.isNaN
        let animChanged = animCount != lastAnimCount

        guard alphaChanged || yChanged || hChanged || animChanged else { return }

        lastAlpha = alpha
        lastY = y
        lastH = h
        lastAnimCount = animCount

        let depth = nav.viewControllers.count
        let top = NavFlashDebug.describe(nav.topViewController)
        let keys = (bar.layer.animationKeys() ?? []).joined(separator: ",")
        let mdlAlpha = bar.layer.opacity
        let mdlHidden = bar.isHidden
        NavFlashDebug.log.debug(
            "watcher[\(self.ownerTag, privacy: .public)] pres.α=\(alpha) y=\(y, format: .fixed(precision: 1)) h=\(h, format: .fixed(precision: 1)) model.α=\(mdlAlpha) hidden=\(mdlHidden) anims=[\(keys, privacy: .public)] depth=\(depth) top=\(top, privacy: .public)"
        )
    }
}
