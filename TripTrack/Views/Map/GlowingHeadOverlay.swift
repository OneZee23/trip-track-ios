import MapKit

/// Custom overlay for the animated "head" of the live track with glow effect
final class GlowingHeadOverlay: NSObject, MKOverlay {
    let coordinates: [CLLocationCoordinate2D]

    var coordinate: CLLocationCoordinate2D {
        coordinates.isEmpty ? CLLocationCoordinate2D() : coordinates[coordinates.count / 2]
    }

    var boundingMapRect: MKMapRect {
        guard !coordinates.isEmpty else { return .null }
        var rect = MKMapRect.null
        for coord in coordinates {
            let point = MKMapPoint(coord)
            let pointRect = MKMapRect(origin: point, size: MKMapSize(width: 1, height: 1))
            rect = rect.union(pointRect)
        }
        return rect.insetBy(dx: -1000, dy: -1000)
    }

    init(coordinates: [CLLocationCoordinate2D]) {
        self.coordinates = coordinates
    }
}

/// Renderer that draws the head segment with a glowing fade effect and tip dot
final class GlowingHeadRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let headOverlay = overlay as? GlowingHeadOverlay,
              headOverlay.coordinates.count >= 2 else { return }

        let coords = headOverlay.coordinates

        // Build path
        let path = CGMutablePath()
        let firstPoint = point(for: MKMapPoint(coords[0]))
        path.move(to: firstPoint)
        for i in 1..<coords.count {
            path.addLine(to: point(for: MKMapPoint(coords[i])))
        }

        let accentColor = UIColor(red: 235/255, green: 87/255, blue: 30/255, alpha: 1)

        // Outer glow (wider, semi-transparent)
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path)
        context.setLineWidth(12.0 / zoomScale)
        context.setStrokeColor(accentColor.withAlphaComponent(0.3).cgColor)
        context.strokePath()
        context.restoreGState()

        // Main bright line
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path)
        context.setLineWidth(5.0 / zoomScale)
        context.setStrokeColor(accentColor.withAlphaComponent(0.95).cgColor)
        context.strokePath()
        context.restoreGState()

        // Tip dot
        let tipPoint = point(for: MKMapPoint(coords.last!))
        let dotRadius: CGFloat = 6.0 / zoomScale

        // White center
        let dotRect = CGRect(x: tipPoint.x - dotRadius, y: tipPoint.y - dotRadius,
                             width: dotRadius * 2, height: dotRadius * 2)
        context.saveGState()
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: dotRect)
        context.restoreGState()

        // Orange ring
        let ringRect = dotRect.insetBy(dx: -2.0 / zoomScale, dy: -2.0 / zoomScale)
        context.saveGState()
        context.setStrokeColor(accentColor.cgColor)
        context.setLineWidth(2.0 / zoomScale)
        context.strokeEllipse(in: ringRect)
        context.restoreGState()
    }
}
