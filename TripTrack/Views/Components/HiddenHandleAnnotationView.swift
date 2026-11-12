import MapKit

final class HiddenHandleAnnotationView: MKAnnotationView {
    var onAdjust: ((Int) -> Void)?
    private let lockView = UIImageView()
    private let bubble = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let titleLabel = UILabel()
    private let captionLabel = UILabel()
    private let pulseLayer = CAShapeLayer()
    private var configuredHandle: HiddenHandle?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 220, height: 86)
        centerOffset = CGPoint(x: 0, y: -32)
        collisionMode = .none
        canShowCallout = false
        clipsToBounds = false

        lockView.frame = CGRect(x: 99.5, y: 64.5, width: 21, height: 21)
        lockView.contentMode = .scaleToFill
        addSubview(lockView)

        bubble.frame = CGRect(x: 0, y: 1, width: 220, height: 52)
        bubble.layer.cornerRadius = 12
        bubble.clipsToBounds = true
        bubble.isUserInteractionEnabled = false
        bubble.isHidden = true
        let labels = UIStackView(arrangedSubviews: [titleLabel, captionLabel])
        labels.axis = .vertical
        labels.spacing = 2
        labels.alignment = .center
        bubble.contentView.addSubview(labels)
        labels.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: bubble.contentView.leadingAnchor, constant: 10),
            labels.trailingAnchor.constraint(equalTo: bubble.contentView.trailingAnchor, constant: -10),
            labels.centerYAnchor.constraint(equalTo: bubble.contentView.centerYAnchor)
        ])
        titleLabel.font = .inter(12, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.78
        captionLabel.font = .inter(10, weight: .medium)
        captionLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        captionLabel.textAlignment = .center
        captionLabel.adjustsFontSizeToFitWidth = true
        captionLabel.minimumScaleFactor = 0.78
        addSubview(bubble)

        pulseLayer.fillColor = UIColor.clear.cgColor
        pulseLayer.strokeColor = UIColor(AppTheme.accent).withAlphaComponent(0.72).cgColor
        pulseLayer.lineWidth = 2
        layer.insertSublayer(pulseLayer, below: lockView.layer)
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
    }

    required init?(coder: NSCoder) { nil }

    func configure(_ handle: HiddenHandle, onAdjust: @escaping (Int) -> Void) {
        let shouldPulse = handle.pulse && configuredHandle?.pulse != true
        let wasLifted = configuredHandle?.lifted ?? false
        let wasBubbleVisible = configuredHandle?.bubbleVisible ?? false
        configuredHandle = handle
        self.onAdjust = onAdjust
        accessibilityIdentifier = handle.id
        image = nil
        lockView.image = Self.image(ghost: handle.ghost)
        if wasLifted != handle.lifted {
            UIView.animate(withDuration: 0.14, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
                self.lockView.transform = handle.lifted ? CGAffineTransform(scaleX: 1.2, y: 1.2) : .identity
            }
        } else {
            lockView.transform = handle.lifted ? CGAffineTransform(scaleX: 1.2, y: 1.2) : .identity
        }
        lockView.layer.shadowColor = UIColor.black.cgColor
        lockView.layer.shadowOpacity = handle.lifted ? 0.35 : 0.16
        lockView.layer.shadowRadius = handle.lifted ? 8 : 3
        lockView.layer.shadowOffset = CGSize(width: 0, height: handle.lifted ? 4 : 1)
        lockView.layer.shadowPath = UIBezierPath(ovalIn: lockView.bounds).cgPath
        titleLabel.text = handle.bubbleTitle
        captionLabel.text = handle.bubbleCaption
        accessibilityLabel = handle.accessibilityLabel
        accessibilityValue = handle.value
        accessibilityTraits = .adjustable
        if wasBubbleVisible != handle.bubbleVisible {
            if handle.bubbleVisible {
                bubble.alpha = 0
                bubble.isHidden = false
                UIView.animate(withDuration: 0.16, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
                    self.bubble.alpha = 1
                }
            } else {
                UIView.animate(withDuration: 0.16, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
                    self.bubble.alpha = 0
                } completion: { finished in
                    guard finished else { return }
                    self.bubble.isHidden = true
                }
            }
        }
        if shouldPulse { pulse() }
    }

    /// The part of the map the bubble may use (above the panel), in the map view's coordinates.
    private var bubbleArea: CGRect = .null

    func clampBubble(in mapBounds: CGRect, coordinatePoint: CGPoint) {
        bubbleArea = mapBounds.insetBy(dx: 0, dy: 8)
        placeBubble()
    }

    /// MapKit moves annotation views by `center`, and it does so AFTER `viewFor` returns and
    /// after a coordinate change: a bubble placed from `frame` at those moments sat where the
    /// view used to be (off screen on a still map, a step behind during a drag). So the bubble
    /// is placed in the view's own coordinates whenever the view itself moves.
    override var center: CGPoint {
        didSet { placeBubble() }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        placeBubble()
    }

    private func placeBubble() {
        let lock = lockView.frame
        let size = bubble.bounds.size
        var origin = CGPoint(x: lock.midX - size.width / 2, y: lock.minY - 11.5 - size.height)
        guard !bubbleArea.isNull, let map = enclosingMapView() else {
            bubble.frame.origin = origin
            return
        }
        let area = convert(bubbleArea, from: map)
        // No room above the lock near the top of the map: show the bubble under it instead
        // of pushing it down onto the lock and the finger.
        if origin.y < area.minY { origin.y = lock.maxY + 11.5 }
        origin.x = min(max(origin.x, area.minX + 8), area.maxX - size.width - 8)
        origin.y = min(max(origin.y, area.minY), area.maxY - size.height)
        bubble.frame.origin = origin
    }

    private func enclosingMapView() -> MKMapView? {
        var view = superview
        while let current = view {
            if let map = current as? MKMapView { return map }
            view = current.superview
        }
        return nil
    }

    override func accessibilityIncrement() { onAdjust?(1) }
    override func accessibilityDecrement() { onAdjust?(-1) }

    /// The 44 pt target around the lock. The view itself is as wide as the bubble, and an
    /// invisible 220 × 86 area must not take touches from the map around a handle.
    private var lockTarget: CGRect { lockView.frame.insetBy(dx: -11.5, dy: -11.5) }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        lockTarget.contains(point)
    }

    /// Computed on every read: MapKit moves annotation views by `center` without a layout
    /// pass, so a frame stored in `layoutSubviews` pointed VoiceOver (and UI tests) at the
    /// place where the view was first laid out, before it even joined the window.
    override var accessibilityFrame: CGRect {
        get { UIAccessibility.convertToScreenCoordinates(lockTarget, in: self) }
        set { }
    }

    private func pulse() {
        pulseLayer.frame = bounds
        pulseLayer.path = UIBezierPath(ovalIn: CGRect(x: 93, y: 58, width: 34, height: 34)).cgPath
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        pulseLayer.removeAnimation(forKey: "handlePulse")
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.7
        scale.toValue = 1.45
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.42
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pulseLayer.add(group, forKey: "handlePulse")
    }

    private static func image(ghost: Bool) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 21, height: 21))
        return renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 21, height: 21)
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: rect)
            let ink = UIColor(ghost ? AppTheme.mapLockInk.opacity(0.58) : AppTheme.mapLockInk)
            context.cgContext.setStrokeColor(ink.cgColor)
            context.cgContext.setLineWidth(ghost ? 1.3 : 0.5)
            if ghost { context.cgContext.setLineDash(phase: 0, lengths: [2.4, 2]) }
            context.cgContext.strokeEllipse(in: rect.insetBy(dx: 0.5, dy: 0.5))
            context.cgContext.setLineDash(phase: 0, lengths: [])
            let symbol = UIImage(systemName: ghost ? "lock.open.fill" : "lock.fill")?
                .withTintColor(ink, renderingMode: .alwaysOriginal)
            symbol?.draw(in: CGRect(x: 6.3, y: 5.5, width: 8.4, height: 10))
        }
    }
}
