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

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            onScrub(gesture.location(in: self))
        case .ended, .cancelled, .failed:
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

    /// Sideways, judged on how far the finger has actually travelled.
    ///
    /// This is the decision the whole file turns on, because a "yes" now locks
    /// the page for the rest of the touch (see `shouldBeRequiredToFailBy`).
    /// It has to be answered on the first few points of travel — waiting longer
    /// is what once made the chart feel dead — and it has to be answered on
    /// DIRECTION rather than on distance, so a vertical drag that happens to
    /// start on the chart is never claimed and the page scrolls immediately.
    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard let pan = gesture as? UIPanGestureRecognizer else { return true }
        let travelled = pan.translation(in: self)
        // A clear horizontal bias, not merely a larger x: a near-diagonal
        // start used to be claimable, and claiming now locks the page for the
        // whole touch, so a wrong answer costs more than it did.
        return abs(travelled.x) > abs(travelled.y) * 1.3 && abs(travelled.x) > 4
    }

    /// The page WAITS for this recogniser instead of running alongside it.
    ///
    /// Simultaneous recognition was the previous answer, and its cost was
    /// written down honestly at the time: «a scrub with a wobbly finger can
    /// nudge the page a few points». On a real finger that is not a few points.
    /// Nobody traces a chart along a perfect horizontal, so the page crept
    /// upward the whole time you were reading — which is the one thing a chart
    /// scrub must never do, and is not how any native chart behaves. In Stocks,
    /// Health and Fitness the page is simply still while your finger is on the
    /// graph.
    ///
    /// So the page's pan is required to fail against this one. The reason that
    /// arrangement was abandoned before was not this rule — it was the begin
    /// threshold that went with it, which demanded a deliberate sideways shove
    /// before the chart would answer, and made the chart feel dead. That
    /// threshold is gone (see `gestureRecognizerShouldBegin`): direction is
    /// decided on the first few points of travel, so a vertical drag never
    /// claims the touch and the page scrolls with no perceptible delay.
    ///
    /// What this costs, stated plainly: a drag that starts sideways and then
    /// turns downward will not scroll the page until the finger lifts. That is
    /// the same bargain Health makes, it is predictable, and it is worth far
    /// more than a page that drifts while you read.
    func gestureRecognizer(
        _ gesture: UIGestureRecognizer,
        shouldBeRequiredToFailBy other: UIGestureRecognizer
    ) -> Bool {
        other.view is UIScrollView
    }
}
