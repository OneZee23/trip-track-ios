import SwiftUI
import UIKit

/// Invisible surface that turns a sideways drag into a stream of positions and
/// lets every other touch fall through to the page.
///
/// This exists because of one hard constraint: the charts live inside a
/// `ScrollView`. A SwiftUI `DragGesture` cannot share a touch with a scroll
/// view on equal terms — as an exclusive gesture it swallows the page scroll,
/// and as a simultaneous one the scroll view cancels it the instant the finger
/// moves, so it only ever fires for touches that stay put. Requiring a hold
/// first works, but it is not what a chart is supposed to feel like: every
/// serious fitness app lets you put a finger down and slide.
///
/// A pan recogniser can do what a `DragGesture` cannot, because it can answer
/// two questions UIKit asks and SwiftUI never exposes: "is this touch mine?"
/// (only if it is moving sideways) and "should the scroll view wait for my
/// answer?" (yes — and the answer comes on the first movement, so a vertical
/// swipe scrolls with no perceptible delay).
struct HorizontalScrubSurface: UIViewRepresentable {
    /// Finger position within the surface, as it moves.
    var onScrub: (CGPoint) -> Void
    /// Finger lifted. The readout stays on screen; this is for releasing any
    /// transient state the caller keeps.
    var onEnded: () -> Void = {}

    func makeUIView(context: Context) -> ScrubSurfaceView {
        let view = ScrubSurfaceView()
        view.onScrub = onScrub
        view.onEnded = onEnded
        return view
    }

    func updateUIView(_ view: ScrubSurfaceView, context: Context) {
        view.onScrub = onScrub
        view.onEnded = onEnded
    }
}

final class ScrubSurfaceView: UIView, UIGestureRecognizerDelegate {
    var onScrub: (CGPoint) -> Void = { _ in }
    var onEnded: () -> Void = {}

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)

        // A tap still reads a single point — the chart answers a poke as well
        // as a slide.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Where the finger was last seen, so each frame can be judged on its own
    /// direction rather than on how the drag started.
    private var lastLocation: CGPoint = .zero

    /// How far the finger has committed to going up or down, in points, after
    /// the sideways part of the movement is subtracted from it. Never negative:
    /// a drag that goes back to travelling sideways starts the count again.
    private var verticalCommitment: CGFloat = 0

    /// Vertical travel, net of sideways travel, that hands the touch back.
    ///
    /// Small on purpose. This is not "how far you must drag to scroll" — the
    /// page has already been held for this long by the time it is reached, and
    /// a finger that has turned downwards wanted the page a good deal earlier.
    static let escapeThreshold: CGFloat = 16

    /// The escape rule itself, as a function of one frame's movement — split
    /// out from the gesture handler so it can be tested without a recogniser,
    /// a scroll view or a finger.
    ///
    /// Vertical travel adds, sideways travel subtracts, and the total never
    /// goes below zero. The clamp is what makes it a rule about the finger's
    /// CURRENT direction: a drag that goes back to reading the chart sideways
    /// spends its way back down to zero and starts over, so a wobble cannot
    /// bank its way to an escape one stray frame at a time.
    static func advanceCommitment(_ current: CGFloat, dx: CGFloat, dy: CGFloat) -> CGFloat {
        max(0, current + abs(dy) - abs(dx))
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            lastLocation = gesture.location(in: self)
            verticalCommitment = 0
            onScrub(lastLocation)
        case .changed:
            let location = gesture.location(in: self)
            let dx = abs(location.x - lastLocation.x)
            let dy = abs(location.y - lastLocation.y)
            lastLocation = location

            // Escape hatch: a drag that starts sideways and then turns into a
            // scroll hands the touch back instead of holding it hostage.
            //
            // Judged frame by frame, because the finger's CURRENT direction is
            // the question and its history is not. Measuring the total offset
            // from where the drag began — which is what this did — asked the
            // wrong question in the worst possible way: every point scrubbed
            // sideways raised the bar for escaping, so the further along the
            // chart you had read, the harder the page became to scroll, and a
            // long scrub could pin it outright. Netting the two directions
            // against each other, and clamping at zero, keeps a wobbly finger
            // from escaping by accident while letting a deliberate turn out
            // within a few frames however the drag started.
            verticalCommitment = Self.advanceCommitment(verticalCommitment, dx: dx, dy: dy)
            if verticalCommitment > Self.escapeThreshold {
                // Cancelling the recogniser (disable/enable is the only way to
                // do that to a stock pan) lets the enclosing scroll view pick
                // the gesture up mid-drag.
                gesture.isEnabled = false
                gesture.isEnabled = true
                verticalCommitment = 0
                onEnded()
                return
            }
            onScrub(location)
        case .ended, .cancelled, .failed:
            verticalCommitment = 0
            onEnded()
        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        onScrub(gesture.location(in: self))
        onEnded()
    }

    // MARK: - UIGestureRecognizerDelegate

    /// Sideways only, and sideways by a clear margin.
    ///
    /// `|vx| > |vy|` was too generous by a hair: a finger heading down the
    /// page with any diagonal drift could satisfy it in the one frame this
    /// is asked, the chart claimed the touch — and because the scroll view
    /// is required to wait for this recogniser (below), the page then could
    /// not scroll at all for the rest of that drag. Requiring the sideways
    /// component to dominate, and to be moving at all, keeps the ambiguous
    /// middle with the page, where a drag that isn't obviously "read the
    /// chart" belongs.
    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard let pan = gesture as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: self)
        return abs(velocity.x) > abs(velocity.y) * 1.6 && abs(velocity.x) > 80
    }

    /// Make the enclosing scroll view wait until this recogniser has decided.
    /// It decides on the first movement — either it claims the touch (and the
    /// page correctly stays put while you read the chart) or it fails and the
    /// page scrolls as though this view were not here.
    func gestureRecognizer(
        _ gesture: UIGestureRecognizer,
        shouldBeRequiredToFailBy other: UIGestureRecognizer
    ) -> Bool {
        gesture is UIPanGestureRecognizer && other.view is UIScrollView
    }
}
