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
    var isRecording: Bool = false
    var onAnnotationSelected: ((MKPointAnnotation) -> Void)?
    var onCameraDistanceChanged: ((Double) -> Void)?
    var onVisibleRectChanged: ((MKMapRect) -> Void)?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator

        mapView.showsUserLocation = true
        mapView.userTrackingMode = userTrackingMode

        mapView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)

        // Initial camera from system cached location
        if let cachedLocation = CLLocationManager().location {
            let camera = MKMapCamera(
                lookingAtCenter: cachedLocation.coordinate,
                fromDistance: 500,
                pitch: 0,
                heading: 0
            )
            mapView.camera = camera
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
            if overlay is FogPolygon {
                let renderer = MKPolygonRenderer(overlay: overlay)
                renderer.fillColor = FogPolygonBuilder.fogColor
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
