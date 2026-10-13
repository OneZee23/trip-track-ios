import MapKit

/// MapKit rasterizes dashed polylines at discrete tile zooms. Between those
/// zooms it stretches the bitmap, while a solid vector route keeps its width.
/// Size the dash in the live viewport's map points, not the tile's zoom bucket.
final class ScreenScaledDashRenderer: MKPolylineRenderer {
    private let scaleLock = NSLock()
    private var screenZoomScale: MKZoomScale?

    /// Called on the main thread. Panning at the same zoom does not invalidate
    /// tiles; a zoom only redraws existing paths, never rebuilds route geometry.
    func updateScreenZoomScale(_ scale: MKZoomScale) {
        guard scale.isFinite, scale > 0 else { return }
        scaleLock.lock()
        // Ignore projection rounding and subpixel changes (< 0.04 pt at 4 pt).
        let changed = screenZoomScale.map { abs(scale / $0 - 1) >= 0.01 } ?? true
        if changed { screenZoomScale = scale }
        scaleLock.unlock()
        // Invalidate every cached zoom, including offscreen tiles. Invalidating
        // just `scale` misses the quantized tile MapKit is stretching right now.
        if changed { setNeedsDisplay() }
    }

    override func applyStrokeProperties(to context: CGContext, atZoomScale zoomScale: MKZoomScale) {
        super.applyStrokeProperties(to: context, atZoomScale: zoomScale)
        // MapKit draws tiles concurrently. Never read the live MKMapView here.
        scaleLock.lock()
        let scale = screenZoomScale
        scaleLock.unlock()
        guard let scale else { return }
        context.setLineWidth(lineWidth / scale)
        context.setLineDash(
            phase: lineDashPhase / scale,
            lengths: (lineDashPattern ?? []).map { CGFloat($0.doubleValue) / scale }
        )
    }

    /// visibleMapRect is an axis-aligned bounding box: width/view.width would
    /// report a different zoom merely from rotating the map. Project a short
    /// horizontal screen segment instead, including the antimeridian wrap.
    static func screenZoomScale(in mapView: MKMapView) -> MKZoomScale? {
        let bounds = mapView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let span = min(bounds.width, 64)
        let left = MKMapPoint(mapView.convert(
            CGPoint(x: bounds.midX - span / 2, y: bounds.midY), toCoordinateFrom: mapView))
        let right = MKMapPoint(mapView.convert(
            CGPoint(x: bounds.midX + span / 2, y: bounds.midY), toCoordinateFrom: mapView))
        let dx = abs(right.x - left.x).truncatingRemainder(dividingBy: MKMapSize.world.width)
        let distance = hypot(min(dx, MKMapSize.world.width - dx), right.y - left.y)
        guard distance.isFinite, distance > 0 else { return nil }
        return span / distance
    }
}
