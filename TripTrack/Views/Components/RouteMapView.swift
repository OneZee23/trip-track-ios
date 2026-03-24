import SwiftUI
import MapKit

// MARK: - SpeedPolyline

/// Custom MKPolyline subclass that carries the speed value for color mapping.
final class SpeedPolyline: MKPolyline {
    var speed: Double = 0 // m/s
}

struct RouteMapView: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]
    var speeds: [Double] = []
    var isInteractive: Bool = false

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        mapView.isScrollEnabled = isInteractive
        mapView.isZoomEnabled = isInteractive
        mapView.isRotateEnabled = isInteractive
        mapView.isPitchEnabled = isInteractive
        mapView.showsCompass = isInteractive
        mapView.showsScale = false
        mapView.preferredConfiguration = MKStandardMapConfiguration(
            elevationStyle: isInteractive ? .realistic : .flat
        )

        if coordinates.count >= 2 {
            if speeds.count == coordinates.count {
                // Build per-segment speed polylines
                let simplified = Self.simplifyWithSpeeds(coordinates, speeds: speeds, epsilon: 0.00003)
                var unionRect: MKMapRect = .null
                for i in 0..<(simplified.coords.count - 1) {
                    var segment = [simplified.coords[i], simplified.coords[i + 1]]
                    let poly = SpeedPolyline(coordinates: &segment, count: 2)
                    poly.speed = simplified.speeds[i]
                    mapView.addOverlay(poly, level: .aboveRoads)
                    unionRect = unionRect.union(poly.boundingMapRect)
                }
                let insets = UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30)
                mapView.setVisibleMapRect(unionRect, edgePadding: insets, animated: false)
            } else {
                let simplified = GeometryUtils.simplifyRDP(coordinates, epsilon: 0.00003)
                let polyline = MKPolyline(coordinates: simplified, count: simplified.count)
                mapView.addOverlay(polyline, level: .aboveRoads)

                let rect = polyline.boundingMapRect
                let insets = UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30)
                mapView.setVisibleMapRect(rect, edgePadding: insets, animated: false)
            }
        }

        // Start / end dots
        if let first = coordinates.first {
            let pin = MKPointAnnotation()
            pin.coordinate = first
            pin.title = "start"
            mapView.addAnnotation(pin)
        }
        if coordinates.count > 1, let last = coordinates.last {
            let pin = MKPointAnnotation()
            pin.coordinate = last
            pin.title = "end"
            mapView.addAnnotation(pin)
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Simplification with speeds

    private struct SimplifiedRoute {
        let coords: [CLLocationCoordinate2D]
        let speeds: [Double] // one per coordinate (segment speed = speeds[i] for segment i→i+1)
    }

    /// Simplify coordinates while keeping associated speed values.
    private static func simplifyWithSpeeds(
        _ coords: [CLLocationCoordinate2D],
        speeds: [Double],
        epsilon: Double
    ) -> SimplifiedRoute {
        guard coords.count > 2 else {
            return SimplifiedRoute(coords: coords, speeds: speeds)
        }
        let indices = GeometryUtils.simplifyIndices(coords, startIndex: 0, endIndex: coords.count - 1, epsilon: epsilon)
        let sortedIndices = indices.sorted()
        let newCoords = sortedIndices.map { coords[$0] }
        let newSpeeds = sortedIndices.map { speeds[$0] }
        return SimplifiedRoute(coords: newCoords, speeds: newSpeeds)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let speedLine = overlay as? SpeedPolyline {
                let renderer = MKPolylineRenderer(polyline: speedLine)
                renderer.strokeColor = Self.color(forSpeedMS: speedLine.speed)
                renderer.lineWidth = 4
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 252/255, green: 76/255, blue: 2/255, alpha: 0.9) // accent
                renderer.lineWidth = 4
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        /// Maps speed (m/s) to a color based on km/h thresholds.
        ///  0-30 km/h  = green  (#2EAE50)
        /// 30-60 km/h  = yellow (#F5BE1E)
        /// 60-90 km/h  = orange (#EB571E)
        ///   90+ km/h  = red    (#DC3C32)
        private static func color(forSpeedMS speed: Double) -> UIColor {
            let kmh = speed * 3.6
            switch kmh {
            case ..<30:
                return UIColor(red: 0x2E/255, green: 0xAE/255, blue: 0x50/255, alpha: 0.9)
            case 30..<60:
                return UIColor(red: 0xF5/255, green: 0xBE/255, blue: 0x1E/255, alpha: 0.9)
            case 60..<90:
                return UIColor(red: 0xEB/255, green: 0x57/255, blue: 0x1E/255, alpha: 0.9)
            default:
                return UIColor(red: 0xDC/255, green: 0x3C/255, blue: 0x32/255, alpha: 0.9)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let point = annotation as? MKPointAnnotation else { return nil }

            let isStart = point.title == "start"
            let id = isStart ? "StartDot" : "EndDot"

            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.canShowCallout = false

            let size: CGFloat = 10
            let color: UIColor = isStart
                ? UIColor(red: 48/255, green: 209/255, blue: 88/255, alpha: 1)
                : UIColor(red: 255/255, green: 69/255, blue: 58/255, alpha: 1)

            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            view.image = renderer.image { ctx in
                color.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: CGSize(width: size, height: size)))
            }
            view.centerOffset = .zero
            return view
        }
    }
}
