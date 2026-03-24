import SwiftUI
import MapKit

struct MapViewRepresentable: UIViewRepresentable {
    @Binding var userTrackingMode: MKUserTrackingMode
    var annotations: [MKPointAnnotation] = []
    var selectedAnnotation: MKPointAnnotation?
    var overlays: [MKOverlay] = []
    var isDarkMap: Bool = false
    var bottomInset: CGFloat = 0
    @Binding var zoomDelta: Double
    var targetCameraDistance: Double = 0
    var onAnnotationSelected: ((MKPointAnnotation) -> Void)?
    var onCameraDistanceChanged: ((Double) -> Void)?

    init(
        userTrackingMode: Binding<MKUserTrackingMode>,
        annotations: [MKPointAnnotation] = [],
        selectedAnnotation: MKPointAnnotation? = nil,
        overlays: [MKOverlay] = [],
        isDarkMap: Bool = false,
        bottomInset: CGFloat = 0,
        zoomDelta: Binding<Double> = .constant(0),
        targetCameraDistance: Double = 0,
        onAnnotationSelected: ((MKPointAnnotation) -> Void)? = nil,
        onCameraDistanceChanged: ((Double) -> Void)? = nil
    ) {
        self._userTrackingMode = userTrackingMode
        self.annotations = annotations
        self.selectedAnnotation = selectedAnnotation
        self.overlays = overlays
        self.isDarkMap = isDarkMap
        self.bottomInset = bottomInset
        self._zoomDelta = zoomDelta
        self.targetCameraDistance = targetCameraDistance
        self.onAnnotationSelected = onAnnotationSelected
        self.onCameraDistanceChanged = onCameraDistanceChanged
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator

        // Native blue dot with heading cone
        mapView.showsUserLocation = true
        mapView.userTrackingMode = userTrackingMode

        // Map configuration
        mapView.preferredConfiguration = MKStandardMapConfiguration(
            elevationStyle: .realistic
        )

        // Native controls
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

        // Sync tracking mode SwiftUI -> UIKit (skip during zoom animation)
        if !context.coordinator.suppressTrackingCallback,
           mapView.userTrackingMode != userTrackingMode {
            mapView.setUserTrackingMode(userTrackingMode, animated: true)
        }

        // Shift map center upward when bottom panel overlaps
        let newInsets = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        if mapView.layoutMargins != newInsets {
            mapView.layoutMargins = newInsets
        }

        // Sync dark/light based on sun
        let style: UIUserInterfaceStyle = isDarkMap ? .dark : .light
        if mapView.overrideUserInterfaceStyle != style {
            mapView.overrideUserInterfaceStyle = style
        }

        // Diff annotations
        let existing = mapView.annotations.compactMap { $0 as? MKPointAnnotation }

        let toRemove = existing.filter { e in
            !annotations.contains(where: { $0 === e })
        }
        if !toRemove.isEmpty {
            mapView.removeAnnotations(toRemove)
        }

        let toAdd = annotations.filter { n in
            !existing.contains(where: { $0 === n })
        }
        if !toAdd.isEmpty {
            mapView.addAnnotations(toAdd)
        }

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

        // Handle zoom delta
        if zoomDelta != 0 {
            let coordinator = context.coordinator
            let camera = (mapView.camera.copy() as? MKMapCamera) ?? mapView.camera
            let factor = zoomDelta > 0 ? 0.5 : 2.0
            camera.centerCoordinateDistance = max(100, camera.centerCoordinateDistance * factor)
            let isFollowing = userTrackingMode != .none

            // Clear any zoom range lock from previous zoom
            mapView.setCameraZoomRange(nil, animated: false)

            if isFollowing, mapView.userLocation.location != nil {
                camera.centerCoordinate = mapView.userLocation.coordinate

                // Cancel any pending restore from previous zoom press
                coordinator.restoreTrackingWork?.cancel()

                // Only disable tracking on the first press in a sequence
                if coordinator.savedTrackingMode == nil {
                    coordinator.savedTrackingMode = userTrackingMode
                    coordinator.suppressTrackingCallback = true
                    mapView.setUserTrackingMode(.none, animated: false)
                }

                // Apply zoom immediately (no completion-based chaining)
                mapView.camera = camera

                // Schedule restore — will be cancelled if another zoom comes quickly
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
                // Free mode → zoom toward screen center
                UIView.animate(withDuration: 0.3) {
                    mapView.camera = camera
                }
            }

            DispatchQueue.main.async { self.zoomDelta = 0 }
        }

        // Auto-zoom based on speed — smooth navigation-style animation.
        let coordinator = context.coordinator
        if targetCameraDistance > 0 {
            let targetChanged = abs(targetCameraDistance - coordinator.lastAnimatedTargetDistance)
                / max(coordinator.lastAnimatedTargetDistance, 1) > 0.3
            if targetChanged {
                let current = mapView.camera.centerCoordinateDistance
                if abs(current - targetCameraDistance) / current > 0.2 {
                    coordinator.lastAnimatedTargetDistance = targetCameraDistance
                    let camera = (mapView.camera.copy() as? MKMapCamera) ?? mapView.camera
                    camera.centerCoordinateDistance = targetCameraDistance
                    if userTrackingMode != .none, mapView.userLocation.location != nil {
                        camera.centerCoordinate = mapView.userLocation.coordinate
                    }
                    UIView.animate(withDuration: 2.5, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                        mapView.camera = camera
                    }
                }
            }
        }

        // Diff overlays
        let existingOverlays = mapView.overlays
        let oldSet = Set(existingOverlays.map { ObjectIdentifier($0 as AnyObject) })
        let newSet = Set(overlays.map { ObjectIdentifier($0 as AnyObject) })

        if oldSet != newSet {
            mapView.removeOverlays(existingOverlays)
            if !overlays.isEmpty {
                mapView.addOverlays(overlays, level: .aboveRoads)
            }
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
        var lastAnimatedTargetDistance: Double = 0

        init(_ parent: MapViewRepresentable) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            guard !suppressTrackingCallback else { return }
            DispatchQueue.main.async {
                if self.parent.userTrackingMode != mode {
                    self.parent.userTrackingMode = mode
                }
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

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
            let callback = parent.onCameraDistanceChanged
            DispatchQueue.main.async {
                callback?(distance)
            }
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let point = view.annotation as? MKPointAnnotation else { return }
            parent.onAnnotationSelected?(point)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
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
