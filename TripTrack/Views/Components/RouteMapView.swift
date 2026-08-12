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

/// Tip extension that closes the visual gap between the last passed
/// waypoint (where `PlaybackPolyline` ends) and the interpolated car
/// position (where `PlaybackCarAnnotation` sits). Without this overlay
/// the white trail visibly lags the car between GPS samples. Always
/// exactly two points; rendered with the same brush as the main trail.
final class PlaybackTipPolyline: MKPolyline {}

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
    /// Bumped by the caller's «+» / «−» buttons. Only the CHANGE matters — the
    /// coordinator remembers the last value it applied, so an unrelated
    /// re-render never re-zooms the map under the user's fingers.
    var zoomTick: Int = 0
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
    /// Camera rides with the playback head instead of framing the whole route.
    /// The car then sits at a FIXED point on screen — the middle — which is
    /// what lets the replay draw a speed bubble over it without projecting
    /// coordinates into view space itself.
    var playbackFollow: Bool = false
    /// Metres across the map while following.
    var playbackFollowSpan: Double = 1400
    /// Padding used when framing the whole route. The replay needs a wider
    /// bottom margin than the previews do — its transport controls sit there.
    var fitInsets: UIEdgeInsets?

    private static let gapThreshold = GeometryUtils.defaultGapThreshold

    /// Smallest rect the preview will zoom to, ~400 m across.
    ///
    /// A trip recorded standing still collapses to a rect of almost no size,
    /// and `setVisibleMapRect` honours it literally: the camera goes to its
    /// maximum zoom, past the level any tiles exist for, and the preview comes
    /// out an empty grey rectangle. A floor keeps the surrounding streets in
    /// frame, so a stationary trip looks like a place instead of a bug.
    private static let minimumSpanMetres: Double = 400

    static func floored(_ rect: MKMapRect) -> MKMapRect {
        let centre = MKMapPoint(x: rect.midX, y: rect.midY)
        let pointsPerMetre = MKMapPointsPerMeterAtLatitude(centre.coordinate.latitude)
        let minimum = minimumSpanMetres * pointsPerMetre
        guard rect.size.width < minimum || rect.size.height < minimum else { return rect }
        let width = max(rect.size.width, minimum)
        let height = max(rect.size.height, minimum)
        return MKMapRect(x: centre.x - width / 2, y: centre.y - height / 2,
                         width: width, height: height)
    }

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
        // Apple requires the Maps attribution to stay visible, and it is laid
        // out against these margins. Without this the replay's transport row
        // sits right on top of it.
        if let fitInsets {
            mapView.layoutMargins = UIEdgeInsets(
                top: 0, left: fitInsets.left,
                bottom: max(0, fitInsets.bottom - 24), right: fitInsets.right
            )
        }

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
                let insets = fitInsets ?? UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30)
                // Remembered so the replay can come back to the whole route
                // after following the car around.
                context.coordinator.overviewRect = unionRect
                context.coordinator.overviewInsets = insets
                mapView.setVisibleMapRect(Self.floored(unionRect), edgePadding: insets, animated: false)

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

        // A trip that never moved — a wait at a barrier, a two-minute test —
        // still has a place, and «where you were» is the one thing the preview
        // can honestly show. Without this the map got a rect of zero size,
        // MapKit zoomed to its limit and drew a blank grey field with a lone
        // dot in it, which reads as a broken map rather than a short trip.
        if coordinates.count < 2, let only = coordinates.first {
            mapView.setVisibleMapRect(
                Self.floored(MKMapRect(origin: MKMapPoint(only), size: MKMapSize(width: 0, height: 0))),
                animated: false
            )
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
        context.coordinator.applyZoom(tick: zoomTick, mapView: mapView)
        context.coordinator.applyPlayback(
            carCoord: playbackCarCoord,
            trailIndex: playbackTrailIndex,
            coords: coordinates,
            mapView: mapView
        )
        context.coordinator.applyCamera(
            follow: playbackFollow,
            car: playbackCarCoord,
            spanMetres: playbackFollowSpan,
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

    /// Map speed to zone index for grouping. Delegates to `SpeedColorScale`
    /// so grouping, polyline colour, and the on-map legend never drift apart.
    private static func speedZone(_ speedMS: Double) -> Int {
        SpeedColorScale.zone(forSpeedMS: speedMS)
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
        /// Last zoom tick applied, so a re-render for any other reason does not
        /// re-run the zoom.
        private var lastZoomTick: Int = 0

        /// One step of the «+» / «−» buttons: halve or double the visible span.
        func applyZoom(tick: Int, mapView: MKMapView) {
            guard tick != lastZoomTick else { return }
            let zoomingIn = tick > lastZoomTick
            lastZoomTick = tick
            var region = mapView.region
            let factor = zoomingIn ? 0.5 : 2.0
            region.span = MKCoordinateSpan(
                latitudeDelta: min(max(region.span.latitudeDelta * factor, 0.0005), 120),
                longitudeDelta: min(max(region.span.longitudeDelta * factor, 0.0005), 120)
            )
            mapView.setRegion(region, animated: true)
        }

        /// The whole-route rect the map opened on, so «обзор» can return to it.
        var overviewRect: MKMapRect = .null
        var overviewInsets = UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30)
        /// Whether the camera is currently riding with the car.
        private var following = false

        /// Camera mode for the replay: ride with the playback head, or frame
        /// the whole route.
        ///
        /// Entering follow mode animates once, to a street-level box around the
        /// car; from then on the centre is moved without animation, every
        /// frame, which is how a navigation camera behaves. Animating each
        /// frame would queue 60 competing animations a second and the map
        /// would visibly lag behind the car.
        func applyCamera(
            follow: Bool,
            car: CLLocationCoordinate2D?,
            spanMetres: Double,
            mapView: MKMapView
        ) {
            guard follow else {
                guard following else { return }
                following = false
                guard !overviewRect.isNull else { return }
                mapView.setVisibleMapRect(
                    RouteMapView.floored(overviewRect),
                    edgePadding: overviewInsets,
                    animated: true
                )
                return
            }
            guard let car else { return }
            if following {
                // Let the zoom-in that started this mode finish. Without the
                // pause the very next playback frame calls setCenter, which
                // cancels the animation — and the camera arrives by a cut
                // rather than by moving there.
                guard CACurrentMediaTime() >= followAnimationUntil else { return }
                mapView.setCenter(car, animated: false)
            } else {
                following = true
                followAnimationUntil = CACurrentMediaTime() + 0.45
                mapView.setRegion(
                    MKCoordinateRegion(
                        center: car,
                        latitudinalMeters: spanMetres,
                        longitudinalMeters: spanMetres
                    ),
                    animated: true
                )
            }
        }

        private var followAnimationUntil: CFTimeInterval = 0

        weak var playbackPolyline: PlaybackPolyline?
        /// Two-point overlay that bridges the gap between the body
        /// trail's end and the interpolated car position. Replaced
        /// every frame so the trail tip tracks the car exactly.
        weak var playbackTip: PlaybackTipPolyline?
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
            // or stopped). Drop annotation + both overlays.
            guard let car = carCoord else {
                if let p = playbackPolyline {
                    mapView.removeOverlay(p)
                    playbackPolyline = nil
                }
                if let t = playbackTip {
                    mapView.removeOverlay(t)
                    playbackTip = nil
                }
                if let c = playbackCar {
                    mapView.removeAnnotation(c)
                    playbackCar = nil
                }
                playbackLastIndex = -1
                return
            }
            // Body trail polyline — replace only when the tail index
            // actually moves to a new original waypoint. This keeps
            // overlay churn bounded by GPS sample count (≤ N swaps per
            // trip), not display refresh rate (≤ 60×duration swaps).
            if trailIndex != playbackLastIndex && trailIndex >= 1 {
                if let p = playbackPolyline {
                    mapView.removeOverlay(p)
                    playbackPolyline = nil
                }
                let safe = min(trailIndex, coords.count - 1)
                var body = Array(coords[0...safe])
                let poly = PlaybackPolyline(coordinates: &body, count: body.count)
                // UNDER the route, not over it. Drawn on top, a solid trail
                // painted out the speed colours behind the car, and by the end
                // of the replay the whole trip was one white line. As a casing
                // beneath it the covered stretch is haloed and still coloured.
                mapView.insertOverlay(
                    poly, at: min(1, mapView.overlays.count), level: .aboveRoads
                )
                playbackPolyline = poly
                playbackLastIndex = trailIndex
            }
            // Tip segment — closes the visual gap between the body
            // trail (ends at last passed waypoint) and the car (sits
            // at the interpolated position between two waypoints). Two
            // points only, so a per-frame swap is cheap — 60×duration
            // overlay swaps of tiny polylines vs whole-trail swaps.
            if trailIndex >= 0 && trailIndex < coords.count {
                if let t = playbackTip {
                    mapView.removeOverlay(t)
                    playbackTip = nil
                }
                var tip = [coords[trailIndex], car]
                let poly = PlaybackTipPolyline(coordinates: &tip, count: 2)
                mapView.insertOverlay(
                    poly, at: min(1, mapView.overlays.count), level: .aboveRoads
                )
                playbackTip = poly
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
                // A white casing, wider than the route, sitting under it: the
                // covered stretch reads as lit up without losing the speed
                // colour that is the whole point of the line.
                renderer.strokeColor = UIColor(red: 0xFF/255, green: 0xFF/255, blue: 0xFF/255, alpha: 1.0)
                renderer.lineWidth = 12
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            if let tip = overlay as? PlaybackTipPolyline {
                // Same brush as the main trail — visually a single
                // continuous polyline from start to car, but cheaper to
                // update because the tip is just 2 points.
                let renderer = MKPolylineRenderer(polyline: tip)
                renderer.strokeColor = UIColor(red: 0xFF/255, green: 0xFF/255, blue: 0xFF/255, alpha: 1.0)
                renderer.lineWidth = 12
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

        /// Maps speed (m/s) to a stroke colour. Thresholds + colours live in
        /// `SpeedColorScale` (shared with the on-map `SpeedLegendView`):
        ///  0-50 green · 50-90 yellow · 90-110 orange · 110+ red (km/h).
        private static func color(forSpeedMS speed: Double) -> UIColor {
            SpeedColorScale.uiColor(forSpeedMS: speed)
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
