import SwiftUI
import UIKit

/// A photo you can pinch, pan, double-tap and swipe away, backed by a real
/// `UIScrollView`.
///
/// Written against UIKit deliberately — this is the one place where the
/// system control is the product. Rubber-banding past the zoom limits,
/// momentum after a flick, panning that stops at the edges of the picture
/// and a double tap that zooms toward the point you tapped are all
/// behaviours people know from every photo app they use, and all of them
/// are free here.
///
/// **The swipe-to-dismiss lives here too, and that is the point.** It used
/// to be a SwiftUI `DragGesture` on the pager above this view. A
/// `DragGesture` has no notion of how many fingers are down, so the first
/// finger of a PINCH already looked like a drag to it, SwiftUI claimed the
/// touch sequence, and the scroll view's pinch recognizer never got to
/// start — which is why zooming only caught on the second or third try. As
/// a `UIPanGestureRecognizer` capped at one finger it cannot see a pinch at
/// all, so two fingers now always mean zoom, first time.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    /// Zoom relative to how the picture rests on screen: 1 = as opened,
    /// >1 = magnified. Normalized, because a photo shaped like the screen
    /// OPENS at a scale above the scroll view's own 1.0 (see `fillCap`).
    var onZoomChange: (CGFloat) -> Void = { _ in }
    /// Single tap that is NOT part of a double tap.
    var onSingleTap: () -> Void = {}
    /// Live vertical translation of a one-finger swipe, for the viewer's
    /// pull-away animation. Only ever fires at rest zoom.
    var onDismissDrag: (CGFloat) -> Void = { _ in }
    /// Translation + predicted end translation when that swipe finishes.
    var onDismissDragEnded: (CGFloat, CGFloat) -> Void = { _, _ in }

    func makeUIView(context: Context) -> ZoomableImageContainer {
        let view = ZoomableImageContainer()
        apply(to: view)
        return view
    }

    func updateUIView(_ view: ZoomableImageContainer, context: Context) {
        apply(to: view)
    }

    private func apply(to view: ZoomableImageContainer) {
        view.onZoomChange = onZoomChange
        view.onSingleTap = onSingleTap
        view.onDismissDrag = onDismissDrag
        view.onDismissDragEnded = onDismissDragEnded
        view.setImage(image)
    }
}

/// Scroll view + image view pair, laid out by hand so the picture fills the
/// screen when its shape allows and is clamped to its own edges once
/// zoomed.
final class ZoomableImageContainer: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    var onZoomChange: (CGFloat) -> Void = { _ in }
    var onSingleTap: () -> Void = {}
    var onDismissDrag: (CGFloat) -> Void = { _ in }
    var onDismissDragEnded: (CGFloat, CGFloat) -> Void = { _, _ in }

    /// How much cropping is worth a full-bleed picture. A phone screenshot
    /// or an ordinary portrait photo is within a few percent of the
    /// screen's shape, so filling it costs almost nothing and removes the
    /// black margins that made the viewer look like it had inset the photo
    /// on purpose. A panorama is nowhere near, and gets fitted — filling it
    /// would throw away most of the picture to avoid two bands of black.
    ///
    /// Deliberately tight: whatever we fill is also the SMALLEST the
    /// picture can be shown (see `minimumZoomScale`), so anything cropped
    /// at rest can only be seen by zooming in and panning. 20% on one axis
    /// is the most that trade is worth.
    private static let fillCap: CGFloat = 1.2

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    /// The scale the picture rests at — 1 for a fitted photo, more for one
    /// that fills. Everything user-facing is measured against THIS, not
    /// against the scroll view's raw `zoomScale`.
    private var baseScale: CGFloat = 1
    /// Guards the layout pass — re-fitting on every `layoutSubviews` would
    /// undo the user's zoom every time the page is re-rendered.
    private var lastLaidOutBounds: CGRect = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        // Content that overflows at REST (the ≤20% fill crop) must not
        // rubber-band: a nested scroll view that bounces at its edge keeps
        // the pan for itself instead of letting the pager have it.
        scrollView.bounces = false
        scrollView.isDirectionalLockEnabled = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear
        // A photo has nothing to "tap through" to, so there is no reason to
        // hold touches back before deciding they are a scroll — holding
        // them is exactly what makes a pinch feel like it needs a moment to
        // catch.
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        addSubview(scrollView)

        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        // Without this a double tap fires the single-tap action first, and
        // the chrome flickers under the zoom the user asked for.
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)

        let dismissPan = UIPanGestureRecognizer(
            target: self, action: #selector(handleDismissPan(_:)))
        // ONE finger. This is what keeps a pinch a pinch — see the type's
        // doc comment.
        dismissPan.maximumNumberOfTouches = 1
        dismissPan.delegate = self
        addGestureRecognizer(dismissPan)
        // The scroll view waits for the dismiss pan to decide. It fails
        // instantly on anything that isn't clearly vertical, so this costs
        // horizontal and zoomed panning nothing — but without it the two
        // race for a downward drag, and on a photo that fills the screen the
        // inner scroll (which can then scroll vertically) tends to win, so
        // swipe-to-dismiss silently stops working on exactly those photos.
        scrollView.panGestureRecognizer.require(toFail: dismissPan)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setImage(_ image: UIImage) {
        guard imageView.image !== image else { return }
        imageView.image = image
        lastLaidOutBounds = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        guard bounds != lastLaidOutBounds, bounds.width > 0, bounds.height > 0 else { return }
        lastLaidOutBounds = bounds

        // The image view is sized to the FITTED picture, so panning a
        // zoomed photo can never wander into empty bands beside it. Filling
        // the screen is then a zoom on top of that, which is also what
        // makes pinching back out to the whole picture possible.
        let size = imageView.image?.size ?? bounds.size
        let fitted: CGSize
        if size.width > 0, size.height > 0 {
            let fit = Swift.min(bounds.width / size.width, bounds.height / size.height)
            // Clamped, because `3024 * (440 / 3024)` evaluates to
            // 440.00000000000006 — a contentSize a hair wider than the
            // bounds, which makes the scroll view horizontally scrollable by
            // six hundredths of a trillionth of a point and lets it contest
            // every sideways swipe.
            fitted = CGSize(
                width: Swift.min(size.width * fit, bounds.width),
                height: Swift.min(size.height * fit, bounds.height)
            )
        } else {
            fitted = bounds.size
        }
        imageView.frame = CGRect(origin: .zero, size: fitted)
        scrollView.contentSize = fitted

        let fill = Swift.max(
            bounds.width / Swift.max(fitted.width, 1),
            bounds.height / Swift.max(fitted.height, 1)
        )
        baseScale = fill <= Self.fillCap ? fill : 1
        // Resting scale IS the floor. Letting a pinch-in go below it left
        // the picture sitting at fit scale with black margins down both
        // sides — a state the viewer never opens in, that the user can't
        // undo except by closing the photo, and that reads as the zoom
        // having broken something. Now pinching in rubber-bands and springs
        // straight back to full-bleed.
        scrollView.minimumZoomScale = baseScale
        // Four times the RESTING size, so "how far can I zoom in" means the
        // same thing whether the photo opened filled or fitted.
        scrollView.maximumZoomScale = baseScale * 4
        scrollView.zoomScale = baseScale
        centreImage()
        onZoomChange(1)
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centreImage()
        onZoomChange(scrollView.zoomScale / baseScale)
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        onZoomChange(scale / baseScale)
    }

    /// Keeps the picture in the middle while it is smaller than the screen,
    /// and pinned to the edges once it is larger.
    private func centreImage() {
        let bounds = scrollView.bounds.size
        var frame = imageView.frame
        frame.origin.x = frame.width < bounds.width ? (bounds.width - frame.width) / 2 : 0
        frame.origin.y = frame.height < bounds.height ? (bounds.height - frame.height) / 2 : 0
        imageView.frame = frame
    }

    private var isAtRestZoom: Bool { scrollView.zoomScale <= baseScale * 1.01 }

    // MARK: - Gestures

    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard let pan = gesture as? UIPanGestureRecognizer else { return true }
        // Zoomed in, the same finger movement is panning around the
        // picture, and horizontal intent belongs to the pager.
        guard isAtRestZoom else { return false }
        let velocity = pan.velocity(in: self)
        // Vertical by a clear margin, not merely by a hair. A near-diagonal
        // flick used to satisfy `|vy| > |vx|` often enough to arm this pan
        // mid-page-turn, and starting it cancels the pager's own touches —
        // which is how a photo could end up parked between two pages. The
        // ratio, plus a floor under the speed, keeps the ambiguous middle
        // with the pager, where a swipe that isn't obviously "put this
        // away" belongs.
        return abs(velocity.y) > abs(velocity.x) * 1.6 && abs(velocity.y) > 120
    }

    @objc private func handleSingleTap() {
        onSingleTap()
    }

    @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .changed:
            onDismissDrag(gesture.translation(in: self).y)
        case .ended, .cancelled, .failed:
            let translation = gesture.translation(in: self).y
            // 0.3s of the current fling, the same horizon UIKit's own
            // paging uses to decide whether a flick counts.
            let predicted = translation + gesture.velocity(in: self).y * 0.3
            onDismissDragEnded(translation, predicted)
        default:
            break
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if !isAtRestZoom {
            scrollView.setZoomScale(baseScale, animated: true)
            return
        }
        // Zoom toward what was tapped, not the middle of the screen — the
        // detail you double-tapped is the reason you double-tapped.
        let target = baseScale * 2.5
        let point = gesture.location(in: imageView)
        let size = CGSize(
            width: scrollView.bounds.width / target,
            height: scrollView.bounds.height / target
        )
        scrollView.zoom(
            to: CGRect(
                origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2),
                size: size
            ),
            animated: true
        )
    }
}
