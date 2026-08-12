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

    /// Sideways only. A finger that is mostly travelling up or down is on its
    /// way past the chart, not reading it.
    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard let pan = gesture as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: self)
        return abs(velocity.x) > abs(velocity.y)
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
