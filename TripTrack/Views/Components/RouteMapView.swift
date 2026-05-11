import SwiftUI
import MapKit

// MARK: - SpeedPolyline

/// Custom MKPolyline subclass that carries the speed value for color mapping.
final class SpeedPolyline: MKPolyline {
    var speed: Double = 0 // m/s
}

/// Marker subclass so the renderer can pick a brighter style for the
/// "now playing" trail without confusing it with the static SpeedPolyline
/// fragments drawn underneath.
final class PlaybackPolyline: MKPolyline {}

/// Annotation that the renderer recognises as the moving "play head" —
/// shown as the pixel-car asset travelling along the route.
final class PlaybackCarAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
}

struct RouteMapView: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]
    var speeds: [Double] = []
    var isInteractive: Bool = false
    var fogCutoffDate: Date?
    /// When true, disable gap-splitting. Preview polylines from the social
    /// feed are already RDP-simplified — points can be several km apart,
    /// which the 1 km gap threshold treats as discontinuities and leaves the
    /// map with zero drawable segments (so no bounding rect, so no zoom).
    var treatAsPreview: Bool = false
    /// Interpolated car position for the current playback frame, or `nil`
    /// when not playing. Pre-computed by `RoutePlaybackController` and
    /// passed through here — the view does not interpolate, it only
    /// renders. Driven by CADisplayLink at the display's native rate.
    var playbackCarCoord: CLLocationCoordinate2D? = nil
    /// Index of the last original GPS coordinate the playback head has
    /// passed. The view checks this against its remembered last value
    /// before swapping the trail polyline overlay — replacing the
    /// overlay every frame is the #1 source of MapKit frame drops, so
    /// we only do it when the trail tip actually advances to a new
    /// real waypoint.
    var playbackTrailIndex: Int = -1

    private static let gapThreshold = GeometryUtils.defaultGapThreshold

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        mapView.isScrollEnabled = isInteractive
        mapView.isZoomEnabled = isInteractive
        mapView.isRotateEnabled = isInteractive
        mapView.isPitchEnabled = isInteractive
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.preferredConfiguration = MKStandardMapConfiguration(
            elevationStyle: isInteractive ? .realistic : .flat
        )

        if coordinates.count >= 2 {
            // Split into continuous segments first, then simplify each.
            // Preview polylines are treated as one solid segment — their
            // points are sparsely sampled so gap detection would shred
            // them into singleton segments that render as nothing.
            let segments: [([CLLocationCoordinate2D], [Double])]
            if treatAsPreview {
                segments = [(coordinates, speeds.count == coordinates.count ? speeds : [])]
            } else if speeds.count == coordinates.count {
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

                // Add fog of war overlay (below route polylines)
                let visitedHashes: Set<String>
                if let cutoff = fogCutoffDate {
                    visitedHashes = TerritoryManager().visitedHashes(before: cutoff)
                } else {
                    visitedHashes = TerritoryManager().visitedGeohashes
                }
                if let fog = FogPolygonBuilder.build(visitedHashes: visitedHashes, visibleRect: mapView.visibleMapRect) {
                    mapView.insertOverlay(fog, at: 0, level: .aboveRoads)
                }
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

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.applyPlayback(
            carCoord: playbackCarCoord,
            trailIndex: playbackTrailIndex,
            coords: coordinates,
            mapView: mapView
        )
    }

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
        weak var playbackPolyline: PlaybackPolyline?
        weak var playbackCar: PlaybackCarAnnotation?
        /// Last coord index used to draw the trail. Stored so we don't
        /// remove + re-add the overlay every frame — only when the
        /// trail's tail actually advanced.
        var playbackLastIndex: Int = -1

        /// Pre-rendered pixel-car bitmap for the playback annotation.
        /// Drawn once at first access; reused across every annotation
        /// view dequeue. Saves a 36×36 `UIGraphicsImageRenderer` pass
        /// each time MapKit recycles the view.
        private static let playbackCarImage: UIImage? = {
            guard let img = UIImage(named: "PixelCar") else { return nil }
            let target = CGSize(width: 36, height: 36)
            let renderer = UIGraphicsImageRenderer(size: target)
            return renderer.image { _ in
                img.draw(in: CGRect(origin: .zero, size: target))
            }
        }()

        func applyPlayback(
            carCoord: CLLocationCoordinate2D?,
            trailIndex: Int,
            coords: [CLLocationCoordinate2D],
            mapView: MKMapView,
        ) {
            guard coords.count >= 2 else { return }
            // Cleanup branch — controller cleared its state (playback ended
            // or stopped). Drop annotation + overlay.
            guard let car = carCoord else {
                if let p = playbackPolyline {
                    mapView.removeOverlay(p)
                    playbackPolyline = nil
                }
                if let c = playbackCar {
                    mapView.removeAnnotation(c)
                    playbackCar = nil
                }
                playbackLastIndex = -1
                return
            }
            // Trail polyline — replace only when the tail index actually
            // moves to a new original waypoint. This keeps overlay churn
            // bounded by the GPS sample count, never by display refresh
            // rate. The visible car (annotation, updated every frame)
            // moves smoothly ahead of the trail tip during the fractional
            // sub-segment.
            if trailIndex != playbackLastIndex && trailIndex >= 1 {
                if let p = playbackPolyline {
                    mapView.removeOverlay(p)
                    playbackPolyline = nil
                }
                let safe = min(trailIndex, coords.count - 1)
                var trail = Array(coords[0...safe])
                let poly = PlaybackPolyline(coordinates: &trail, count: trail.count)
                mapView.addOverlay(poly, level: .aboveLabels)
                playbackPolyline = poly
                playbackLastIndex = trailIndex
            }
            // Car position — KVO-observed `@objc dynamic coordinate` on
            // PlaybackCarAnnotation lets MapKit reposition the view
            // without any overlay churn. Frame cadence comes from the
            // controller's CADisplayLink.
            if let annotation = playbackCar {
                annotation.coordinate = car
            } else {
                let annotation = PlaybackCarAnnotation(coordinate: car)
                mapView.addAnnotation(annotation)
                playbackCar = annotation
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is FogOverlay {
                return FogOverlayRenderer(overlay: overlay)
            }
            if let playback = overlay as? PlaybackPolyline {
                let renderer = MKPolylineRenderer(polyline: playback)
                // Bright accent + thicker stroke so the trail is visibly
                // "this is what you've covered so far" against the static
                // route underneath.
                renderer.strokeColor = UIColor(red: 0xFF/255, green: 0xFF/255, blue: 0xFF/255, alpha: 1.0)
                renderer.lineWidth = 6
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
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
            // Pixel-car play head for route playback. Image is the
            // pre-rendered `playbackCarImage` static — set once per
            // dequeue, never re-rasterised.
            if annotation is PlaybackCarAnnotation {
                let id = "PlaybackCar"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.canShowCallout = false
                view.image = Self.playbackCarImage
                view.centerOffset = .zero
                view.layer.zPosition = 1000
                return view
            }
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
