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

    private static let gapThreshold = GeometryUtils.defaultGapThreshold

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
            // Split into continuous segments first, then simplify each
            let segments: [([CLLocationCoordinate2D], [Double])]
            if speeds.count == coordinates.count {
                segments = Self.splitIntoSegments(coordinates, speeds: speeds, gapThreshold: Self.gapThreshold)
            } else {
                segments = Self.splitIntoSegments(coordinates, speeds: [], gapThreshold: Self.gapThreshold)
            }

            var unionRect: MKMapRect = .null

            for (segCoords, segSpeeds) in segments {
                guard segCoords.count >= 2 else { continue }

                if segSpeeds.count == segCoords.count {
                    let simplified = Self.simplifyWithSpeeds(segCoords, speeds: segSpeeds, epsilon: 0.0001)
                    // Group consecutive points in the same speed zone into single polylines
                    let grouped = Self.groupBySpeedZone(simplified)
                    for group in grouped {
                        var coords = group.coords
                        let poly = SpeedPolyline(coordinates: &coords, count: coords.count)
                        poly.speed = group.speed
                        mapView.addOverlay(poly, level: .aboveRoads)
                        unionRect = unionRect.union(poly.boundingMapRect)
                    }
                } else {
                    let simplified = GeometryUtils.simplifyRDP(segCoords, epsilon: 0.0001)
                    var mutable = simplified
                    let polyline = MKPolyline(coordinates: &mutable, count: mutable.count)
                    mapView.addOverlay(polyline, level: .aboveRoads)
                    unionRect = unionRect.union(polyline.boundingMapRect)
                }
            }

            if !unionRect.isNull {
                let insets = UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30)
                mapView.setVisibleMapRect(unionRect, edgePadding: insets, animated: false)
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

    // MARK: - Gap Detection (with parallel speeds array)

    /// Split coordinates + speeds into continuous segments, breaking at gaps > threshold.
    /// Extends GeometryUtils.splitByGaps with parallel speed array support.
    private static func splitIntoSegments(
        _ coords: [CLLocationCoordinate2D],
        speeds: [Double],
        gapThreshold: Double
    ) -> [([CLLocationCoordinate2D], [Double])] {
        guard coords.count >= 2 else { return [(coords, speeds)] }
        let hasSpeeds = speeds.count == coords.count
        var segments: [([CLLocationCoordinate2D], [Double])] = []
        var curCoords: [CLLocationCoordinate2D] = [coords[0]]
        var curSpeeds: [Double] = hasSpeeds ? [speeds[0]] : []
        for i in 1..<coords.count {
            if GeometryUtils.haversineDistance(coords[i - 1], coords[i]) > gapThreshold {
                if curCoords.count >= 2 { segments.append((curCoords, curSpeeds)) }
                curCoords = [coords[i]]
                curSpeeds = hasSpeeds ? [speeds[i]] : []
            } else {
                curCoords.append(coords[i])
                if hasSpeeds { curSpeeds.append(speeds[i]) }
            }
        }
        if curCoords.count >= 2 { segments.append((curCoords, curSpeeds)) }
        return segments
    }

    // MARK: - Speed Zone Grouping

    private struct SpeedGroup {
        var coords: [CLLocationCoordinate2D]
        let speed: Double // representative speed for color
    }

    /// Group consecutive points that fall in the same speed color zone into single polylines.
    /// Reduces overlay count from O(points) to O(zone_changes).
    private static func groupBySpeedZone(_ route: SimplifiedRoute) -> [SpeedGroup] {
        guard route.coords.count >= 2 else { return [] }
        var groups: [SpeedGroup] = []
        var currentZone = speedZone(route.speeds[0])
        var currentCoords: [CLLocationCoordinate2D] = [route.coords[0]]
        var currentSpeed = route.speeds[0]

        for i in 1..<route.coords.count {
            let zone = speedZone(route.speeds[i])
            if zone == currentZone {
                currentCoords.append(route.coords[i])
            } else {
                // Close current group (overlap last point for continuity)
                currentCoords.append(route.coords[i])
                groups.append(SpeedGroup(coords: currentCoords, speed: currentSpeed))
                // Start new group from this point
                currentZone = zone
                currentCoords = [route.coords[i]]
                currentSpeed = route.speeds[i]
            }
        }
        if currentCoords.count >= 2 {
            groups.append(SpeedGroup(coords: currentCoords, speed: currentSpeed))
        }
        return groups
    }

    /// Map speed to zone index for grouping (matches color thresholds in Coordinator).
    private static func speedZone(_ speedMS: Double) -> Int {
        let kmh = speedMS * 3.6
        switch kmh {
        case ..<50:  return 0
        case 50..<90: return 1
        case 90..<110: return 2
        default: return 3
        }
    }

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
        ///  0-50  km/h = green  (#2EAE50)
        /// 50-90  km/h = yellow (#F5BE1E)
        /// 90-110 km/h = orange (#EB571E)
        ///  110+  km/h = red    (#DC3C32)
        private static func color(forSpeedMS speed: Double) -> UIColor {
            let kmh = speed * 3.6
            switch kmh {
            case ..<50:
                return UIColor(red: 0x2E/255, green: 0xAE/255, blue: 0x50/255, alpha: 0.9)
            case 50..<90:
                return UIColor(red: 0xF5/255, green: 0xBE/255, blue: 0x1E/255, alpha: 0.9)
            case 90..<110:
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
