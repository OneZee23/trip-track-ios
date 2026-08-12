import SwiftUI
import UIKit

/// A photo you can pinch, pan and double-tap, backed by a real `UIScrollView`.
///
/// Written against UIKit deliberately — this is the one place where the system
/// control is the product. Rubber-banding past the zoom limits, momentum after
/// a flick, panning that stops at the edges of the picture and a double tap
/// that zooms toward the point you tapped are all behaviours people know from
/// every photo app they use, and all of them are free here. The SwiftUI
/// gesture version this replaces had none of them: a pinch-out from fit scale
/// shrank the picture to a stamp and then snapped it back, because a raw
/// `MagnificationGesture` has no notion of a limit to bounce against.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    /// Live zoom scale, so the viewer can switch its own swipe gestures off
    /// while the picture is magnified.
    var onZoomChange: (CGFloat) -> Void = { _ in }
    /// Single tap that is NOT part of a double tap.
    var onSingleTap: () -> Void = {}

    func makeUIView(context: Context) -> ZoomableImageContainer {
        let view = ZoomableImageContainer()
        view.onZoomChange = onZoomChange
        view.onSingleTap = onSingleTap
        view.setImage(image)
        return view
    }

    func updateUIView(_ view: ZoomableImageContainer, context: Context) {
        view.onZoomChange = onZoomChange
        view.onSingleTap = onSingleTap
        view.setImage(image)
    }
}

/// Scroll view + image view pair, laid out by hand so the picture is always
/// centred at fit scale and clamped to its own edges once zoomed.
final class ZoomableImageContainer: UIView, UIScrollViewDelegate {
    var onZoomChange: (CGFloat) -> Void = { _ in }
    var onSingleTap: () -> Void = {}

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    /// Guards the layout pass — re-fitting on every `layoutSubviews` would
    /// undo the user's zoom every time the page is re-rendered.
    private var lastLaidOutBounds: CGRect = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.maximumZoomScale = 4
        scrollView.minimumZoomScale = 1
        scrollView.bouncesZoom = true
        // Content always fits at scale 1, so bouncing would only fight the
        // viewer's own swipe-down-to-close.
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear
        addSubview(scrollView)

        // The frame is sized to the picture itself (below), so the view's own
        // aspect handling has nothing left to do.
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        // Without this a double tap fires the single-tap action first, and the
        // viewer closes underneath the zoom the user asked for.
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
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
        // A rotation or a size change starts the picture over at fit scale —
        // any previous zoom refers to a layout that no longer exists.
        scrollView.zoomScale = 1
        // Fit the frame to the PICTURE, not to the screen. A full-bleed frame
        // with an aspect-fit image inside it hides empty bands above and below
        // the photo, and zoomed in you can pan into that emptiness — the
        // picture wanders off and there is nothing where it used to be.
        let size = imageView.image?.size ?? bounds.size
        let fitted: CGSize
        if size.width > 0, size.height > 0 {
            let scale = Swift.min(bounds.width / size.width, bounds.height / size.height)
            fitted = CGSize(width: size.width * scale, height: size.height * scale)
        } else {
            fitted = bounds.size
        }
        imageView.frame = CGRect(origin: .zero, size: fitted)
        scrollView.contentSize = fitted
        centreImage()
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centreImage()
        onZoomChange(scrollView.zoomScale)
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        onZoomChange(scale)
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

    // MARK: - Taps

    @objc private func handleSingleTap() {
        onSingleTap()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return
        }
        // Zoom toward what was tapped, not the middle of the screen — the
        // detail you double-tapped is the reason you double-tapped.
        let target: CGFloat = 2.5
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
