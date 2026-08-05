import MapKit

/// Route segment carrying its own gradient stops for
/// `MKGradientPolylineRenderer` (same pattern as RouteMapView's
/// `SpeedPolyline`, but with Figma's My-Map palette).
final class SpeedGradientPolyline: MKPolyline {
    var gradientColors: [UIColor] = []
    var gradientLocations: [CGFloat] = []
}

/// Figma: route path re-stroked at width 18, #EB571E 22%, Gaussian blur 11.
/// MapKit can't blur cheaply, so three concentric soft passes approximate it
/// (precedent: GlowingHeadRenderer). Widths are screen points → divided by
/// zoomScale when stroking manually.
final class TerritoryGlowRenderer: MKOverlayRenderer {
    private let multiPolyline: MKMultiPolyline

    init(glow: MKMultiPolyline) {
        self.multiPolyline = glow
        super.init(overlay: glow)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let amber = UIColor(red: 235/255, green: 87/255, blue: 30/255, alpha: 1)
        let path = CGMutablePath()

        for polyline in multiPolyline.polylines {
            let points = polyline.points()
            guard polyline.pointCount >= 2 else { continue }
            // Skip segments far outside the tile being drawn.
            guard mapRect.intersects(polyline.boundingMapRect.insetBy(dx: -mapRect.width, dy: -mapRect.height)) else { continue }
            path.move(to: point(for: points[0]))
            for i in 1..<polyline.pointCount {
                path.addLine(to: point(for: points[i]))
            }
        }
        guard !path.isEmpty else { return }

        context.setLineCap(.round)
        context.setLineJoin(.round)
        for (width, alpha) in [(26.0, 0.07), (18.0, 0.12), (12.0, 0.10)] {
            context.saveGState()
            context.addPath(path)
            context.setLineWidth(CGFloat(width) / zoomScale)
            context.setStrokeColor(amber.withAlphaComponent(alpha).cgColor)
            context.strokePath()
            context.restoreGState()
        }
    }
}

/// City dot: constant-screen-size annotation (8.4 pt accent circle with a
/// 1.6 pt white ring).
final class CityDotAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let cityName: String

    init(coordinate: CLLocationCoordinate2D, cityName: String) {
        self.coordinate = coordinate
        self.cityName = cityName
    }
}

final class CityDotView: MKAnnotationView {
    static let reuseID = "CityDot"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 8.4, height: 8.4)
        layer.cornerRadius = 4.2
        layer.borderWidth = 1.6
        layer.borderColor = UIColor.white.cgColor
        backgroundColor = UIColor(red: 235/255, green: 87/255, blue: 30/255, alpha: 1)
        isEnabled = false
        displayPriority = .defaultHigh
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unused") }
}
