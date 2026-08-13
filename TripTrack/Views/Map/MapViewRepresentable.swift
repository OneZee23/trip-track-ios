import SwiftUI
import MapKit
import OSLog

/// Live-map render diagnostics. A blanket overlay teardown every frame is the
/// "route line blinks" fingerprint — we log only the pathological full rebuild
/// (`.notice`, exported), so the field signal is loud but the steady state quiet.
private let renderLog = Logger(subsystem: "com.triptrack", category: "render")

struct MapViewRepresentable: UIViewRepresentable {
    @Binding var userTrackingMode: MKUserTrackingMode
    var annotations: [MKPointAnnotation] = []
    var selectedAnnotation: MKPointAnnotation?
    var overlays: [MKOverlay] = []
    var isDarkMap: Bool = false
    var bottomInset: CGFloat = 0
    @Binding var zoomDelta: Double
    var isRecording: Bool = false
    var onAnnotationSelected: ((MKPointAnnotation) -> Void)?
    var onCameraDistanceChanged: ((Double) -> Void)?
    var onVisibleRectChanged: ((MKMapRect) -> Void)?
    var onFogRendererCreated: ((FogOverlayRenderer) -> Void)?
    /// Fires once when the map first finishes rendering. Lets the host clear its
    /// loading spinner from a real signal instead of a fragile timed Task.
    var onMapReady: (() -> Void)?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator

        mapView.showsUserLocation = true
        mapView.userTrackingMode = userTrackingMode

        mapView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)

        // Initial camera. Prefer the system's cached fix (tight zoom). On a
        // first-ever launch there's no cached fix, so fall back to a country-
        // level camera instead of leaving the map at the blank grey world
        // origin (which reads as "still loading"); a live fix recenters via
        // follow mode once permission is granted.
        if let cachedLocation = CLLocationManager().location {
            mapView.camera = MKMapCamera(
                lookingAtCenter: cachedLocation.coordinate,
                fromDistance: 500, pitch: 0, heading: 0
            )
        } else {
            mapView.camera = MKMapCamera(
                lookingAtCenter: CLLocationCoordinate2D(latitude: 55.75, longitude: 37.62),
                fromDistance: 1_000_000, pitch: 0, heading: 0
            )
        }

        mapView.preferredConfiguration = MKStandardMapConfiguration(
            elevationStyle: .realistic
        )

        mapView.showsCompass = false
        mapView.showsScale = true
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        // Tracking mode sync
        if !context.coordinator.suppressTrackingCallback,
           mapView.userTrackingMode != userTrackingMode {
            mapView.setUserTrackingMode(userTrackingMode, animated: true)
        }

        // Bottom inset
        let newInsets = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        if mapView.layoutMargins != newInsets {
            mapView.layoutMargins = newInsets
        }

        // Lock map interaction during recording (static mini-map)
        mapView.isScrollEnabled = !isRecording
        mapView.isZoomEnabled = !isRecording
        mapView.isRotateEnabled = !isRecording
        mapView.isPitchEnabled = !isRecording

        // Dark/light map
        let style: UIUserInterfaceStyle = isDarkMap ? .dark : .light
        if mapView.overrideUserInterfaceStyle != style {
            mapView.overrideUserInterfaceStyle = style
        }

        // Diff annotations
        let existing = mapView.annotations.compactMap { $0 as? MKPointAnnotation }
        let toRemove = existing.filter { e in !annotations.contains(where: { $0 === e }) }
        if !toRemove.isEmpty { mapView.removeAnnotations(toRemove) }
        let toAdd = annotations.filter { n in !existing.contains(where: { $0 === n }) }
        if !toAdd.isEmpty { mapView.addAnnotations(toAdd) }

        // Sync selection
        if let selected = selectedAnnotation {
            if mapView.selectedAnnotations.first as? MKPointAnnotation !== selected {
                mapView.selectAnnotation(selected, animated: true)
            }
        } else {
            for ann in mapView.selectedAnnotations {
                mapView.deselectAnnotation(ann, animated: true)
            }
        }

        // Manual zoom buttons (idle mode only)
        if zoomDelta != 0, !isRecording {
            let coordinator = context.coordinator
            let camera = (mapView.camera.copy() as? MKMapCamera) ?? mapView.camera
            let factor = zoomDelta > 0 ? 0.5 : 2.0
            camera.centerCoordinateDistance = max(100, camera.centerCoordinateDistance * factor)
            let isFollowing = userTrackingMode != .none

            mapView.setCameraZoomRange(nil, animated: false)

            if isFollowing, mapView.userLocation.location != nil {
                camera.centerCoordinate = mapView.userLocation.coordinate
                coordinator.restoreTrackingWork?.cancel()

                if coordinator.savedTrackingMode == nil {
                    coordinator.savedTrackingMode = userTrackingMode
                    coordinator.suppressTrackingCallback = true
                    mapView.setUserTrackingMode(.none, animated: false)
                }

                mapView.camera = camera

                let modeToRestore = coordinator.savedTrackingMode ?? userTrackingMode
                let restoreWork = DispatchWorkItem { [weak coordinator] in
                    guard let coordinator, coordinator.savedTrackingMode != nil else { return }
                    let dist = mapView.camera.centerCoordinateDistance
                    let range = MKMapView.CameraZoomRange(
                        minCenterCoordinateDistance: dist,
                        maxCenterCoordinateDistance: dist
                    )
                    mapView.setCameraZoomRange(range, animated: false)
                    coordinator.suppressTrackingCallback = false
                    coordinator.savedTrackingMode = nil
                    mapView.setUserTrackingMode(modeToRestore, animated: true)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        mapView.setCameraZoomRange(nil, animated: false)
                    }
                }
                coordinator.restoreTrackingWork = restoreWork
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: restoreWork)
            } else {
                UIView.animate(withDuration: 0.3) {
                    mapView.camera = camera
                }
            }

            DispatchQueue.main.async { self.zoomDelta = 0 }
        }

        // Diff overlays surgically (mirrors the annotation diff above). The old
        // code removed ALL overlays and re-added ALL of them whenever the
        // ObjectIdentifier set differed — and the glowing head segment
        // republishes at up to 60fps with a fresh identity, so that compare
        // ALWAYS differed and tore down + re-added the unchanged route polyline
        // every frame, which MapKit rendered as the orange line blinking. Now we
        // only touch overlays that actually changed; the route line stays put.
        let existingOverlays = mapView.overlays
        let toRemoveOverlays = existingOverlays.filter { e in !overlays.contains(where: { $0 === e }) }
        if !toRemoveOverlays.isEmpty { mapView.removeOverlays(toRemoveOverlays) }
        for overlay in overlays where !existingOverlays.contains(where: { $0 === overlay }) {
            // Deterministic z-order via overlay LEVELS so it can't depend on
            // which layer was re-added last. Fog is pinned to the bottom of
            // .aboveRoads; the route line sits above it on the same level; the
            // glowing head goes on the higher .aboveLabels level so it's ALWAYS
            // on top — even right after the route polyline is rebuilt (every
            // 0.5s) or while parked (when both publishers go quiet). Without the
            // level split, a re-added route would cover the head.
            if overlay is FogOverlay {
                mapView.insertOverlay(overlay, at: 0, level: .aboveRoads)
            } else if overlay is GlowingHeadOverlay {
                mapView.addOverlay(overlay, level: .aboveLabels)
            } else {
                mapView.addOverlay(overlay, level: .aboveRoads)
            }
        }
        // Regression alarm: a FULL teardown of a multi-overlay set DURING
        // recording is the blink fingerprint. Gated on isRecording so a normal
        // trip-stop clear (fog-only swap, recording=false) doesn't cry wolf.
        if self.isRecording, existingOverlays.count > 1,
           toRemoveOverlays.count == existingOverlays.count {
            renderLog.notice("overlays full rebuild: removed=\(toRemoveOverlays.count, privacy: .public) new=\(overlays.count, privacy: .public)")
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable
        var suppressTrackingCallback = false
        var restoreTrackingWork: DispatchWorkItem?
        var savedTrackingMode: MKUserTrackingMode?
        var didSendInitialRect = false

        init(_ parent: MapViewRepresentable) {
            self.parent = parent
        }

        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            guard !didSendInitialRect else { return }
            didSendInitialRect = true
            let rect = mapView.visibleMapRect
            DispatchQueue.main.async {
                self.parent.onVisibleRectChanged?(rect)
                // Real "the map is up" signal — clears the host's loading spinner.
                self.parent.onMapReady?()
            }
        }

        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            guard !suppressTrackingCallback else { return }
            DispatchQueue.main.async {
                if self.parent.userTrackingMode != mode {
                    self.parent.userTrackingMode = mode
                }
            }
        }

        /// Pre-rendered pixel-car bitmap for the "you are here" marker.
        /// Rasterised once and reused across every dequeue, the same way
        /// `RouteMapView` prepares the replay play head.
        ///
        /// Aspect-fitted into the canon's 44pt box (146:1183) instead of drawn
        /// into it: the sprite is 254×188, so a square draw rect squashes it.
        /// Nearest-neighbour matches the `.interpolation(.none)` every other
        /// surface uses for this art — smoothed, the pixels smear.
        private static let userCarImage: UIImage? = {
            guard let sprite = UIImage(named: "PixelCar") else { return nil }
            let box = CGSize(width: 44, height: 44)
            let ratio = min(box.width / sprite.size.width, box.height / sprite.size.height)
            let fitted = CGSize(width: sprite.size.width * ratio, height: sprite.size.height * ratio)
            let origin = CGPoint(x: (box.width - fitted.width) / 2,
                                 y: (box.height - fitted.height) / 2)
            return UIGraphicsImageRenderer(size: box).image { ctx in
                ctx.cgContext.interpolationQuality = .none
                sprite.draw(in: CGRect(origin: origin, size: fitted))
            }
        }()

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // The pixel car is the app's marker for "you", and the recording
            // map — the one screen where you are actually driving — was the
            // last one still handing the job to MapKit's stock blue puck.
            // No rotation: the replay's play head doesn't rotate either, and
            // MapKit keeps annotation views upright while `.followWithHeading`
            // turns the map under them. A missing asset falls through to the
            // puck rather than to no marker at all.
            if annotation is MKUserLocation {
                guard let carImage = Self.userCarImage else { return nil }
                let carIdentifier = "UserPixelCar"
                let carView = mapView.dequeueReusableAnnotationView(withIdentifier: carIdentifier)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: carIdentifier)
                carView.annotation = annotation
                carView.canShowCallout = false
                // Nothing to open on tap; selectable, it would swallow taps
                // meant for the map under it.
                carView.isEnabled = false
                carView.image = carImage
                carView.centerOffset = .zero
                carView.layer.zPosition = 1000
                return carView
            }

            let identifier = "SearchPin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)

            view.annotation = annotation
            view.markerTintColor = .systemBlue
            view.glyphImage = UIImage(systemName: "mappin")
            view.canShowCallout = true
            return view
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let distance = mapView.camera.centerCoordinateDistance
            let cameraCallback = parent.onCameraDistanceChanged
            let rectCallback = parent.onVisibleRectChanged
            let visibleRect = mapView.visibleMapRect
            DispatchQueue.main.async {
                cameraCallback?(distance)
                rectCallback?(visibleRect)
            }
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let point = view.annotation as? MKPointAnnotation else { return }
            parent.onAnnotationSelected?(point)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is FogOverlay {
                let renderer = FogOverlayRenderer(overlay: overlay)
                DispatchQueue.main.async { [weak self] in
                    self?.parent.onFogRendererCreated?(renderer)
                }
                return renderer
            }
            if let headOverlay = overlay as? GlowingHeadOverlay {
                return GlowingHeadRenderer(overlay: headOverlay)
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 235/255, green: 87/255, blue: 30/255, alpha: 0.8)
                renderer.lineWidth = 4
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
