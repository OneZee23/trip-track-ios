import UIKit

/// Counts the fingers on the map so a tap can be told apart from the tail of a
/// two-finger gesture.
///
/// Pinching out to see more of the map kept opening a region: two fingers
/// almost never land or lift together, and the straggler — short, barely
/// moved — is a textbook tap as far as `UITapGestureRecognizer` is concerned.
///
/// This is deliberately not built on MapKit's own recognisers. Reaching into
/// `map.gestureRecognizers` to find its pinch and require failure of it works
/// until the day MapKit rearranges them, and it says nothing about the
/// two-finger *tap* that zooms out — which has no pinch at all. Counting
/// touches answers both, and answers them the same way next release.
///
/// It never leaves `.possible`, so it recognises nothing, blocks nothing and
/// delays nothing. The count comes from the event rather than from adding and
/// subtracting as touches arrive: a dropped `touchesEnded` would otherwise
/// leave the counter stuck above zero and swallow every tap from then on.
final class FingerWatch: UIGestureRecognizer {
    private(set) var activeTouches = 0
    private var lastMultiTouch: CFTimeInterval?

    /// How long ago the last two-finger moment was, or nil if there has not
    /// been one.
    var secondsSinceMultiTouch: Double? {
        lastMultiTouch.map { CACurrentMediaTime() - $0 }
    }

    /// A tap belongs to a two-finger gesture if a second finger is still down,
    /// or if one was down a moment ago. The window covers the gap between the
    /// two fingers lifting, which is where the stray taps came from.
    static let multiTouchGrace: Double = 0.45

    static func shouldIgnoreTap(activeTouches: Int, secondsSinceMultiTouch: Double?) -> Bool {
        if activeTouches > 1 { return true }
        guard let elapsed = secondsSinceMultiTouch else { return false }
        return elapsed < multiTouchGrace
    }

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    convenience init() { self.init(target: nil, action: nil) }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        sync(event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        sync(event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        sync(event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        sync(event)
    }

    override func reset() {
        super.reset()
        activeTouches = 0
    }

    private func sync(_ event: UIEvent) {
        let live = (event.allTouches ?? []).filter {
            $0.phase != .ended && $0.phase != .cancelled
        }
        activeTouches = live.count
        // Recorded on the way in AND on the way out, so the grace window is
        // measured from the moment the gesture truly finished.
        if live.count > 1 || (event.allTouches ?? []).count > 1 {
            lastMultiTouch = CACurrentMediaTime()
        }
    }
}
