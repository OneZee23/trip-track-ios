import SwiftUI
import MapKit

/// The night memory-map: always-dark muted MapKit base with the amber
/// territory glow and speed-gradient route layers toggled by the «Маршруты ·
/// Территория · Всё» segment (city dots stay visible in every mode).
struct MyMapRepresentable: UIViewRepresentable {
    var glow: MKMultiPolyline?
    var routeSegments: [SpeedGradientPolyline]
    var cityDots: [MyMapViewModel.CityDot]
    var mode: MyMapMode
    /// Fires when the camera settles (regionDidChangeAnimated) — drives the
    /// stats-plate morph. Also used for fullscreen camera continuity.
    var onCameraSettled: ((MKCoordinateRegion) -> Void)? = nil
    /// Camera to restore on first layout (fullscreen hand-off), nil = fit data.
    var initialRegion: MKCoordinateRegion? = nil
    /// One-shot external camera command applied AFTER the initial camera
    /// (fullscreen → main return handoff). Applied once per distinct value.
    var handoffRegion: MKCoordinateRegion? = nil

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        map.preferredConfiguration = config
        // The memory map is ALWAYS night — Figma draws it dark regardless of
        // app theme (unlike the tracking map's sun-driven isDarkMap).
        map.overrideUserInterfaceStyle = .dark
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsScale = false
        map.delegate = context.coordinator
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onCameraSettled = onCameraSettled

        // Re-sync overlays only when the data instances or mode changed —
        // never blanket-remove on every SwiftUI pass (ScratchMapView's
        // remove-all anti-pattern caused visible flashes).
        let dataChanged = coordinator.installedGlow !== glow
            || coordinator.installedSegmentCount != routeSegments.count
        let modeChanged = coordinator.installedMode != mode

        if dataChanged || modeChanged {
            map.removeOverlays(map.overlays)
            if mode.showsTerritory, let glow {
                map.addOverlay(glow, level: .aboveRoads)
            }
            if mode.showsRoutes {
                map.addOverlays(routeSegments, level: .aboveRoads)
            }
            coordinator.installedGlow = glow
            coordinator.installedSegmentCount = routeSegments.count
            coordinator.installedMode = mode

            if dataChanged {
                let dots = cityDots.map { CityDotAnnotation(coordinate: $0.coordinate, cityName: $0.id) }
                map.removeAnnotations(map.annotations)
                map.addAnnotations(dots)
            }
        }

        coordinator.applyInitialCameraIfNeeded(map, glow: glow, initialRegion: initialRegion)
        coordinator.applyHandoffIfNeeded(map, handoffRegion: handoffRegion)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onCameraSettled: ((MKCoordinateRegion) -> Void)?
        var installedGlow: MKMultiPolyline?
        var installedSegmentCount = -1
        var installedMode: MyMapMode?
        var didSetInitialCamera = false
        private var cameraRetryScheduled = false
        private var appliedHandoff: MKCoordinateRegion?

        /// The initial camera must not be applied while the map still has a
        /// zero frame (setRegion on an unlaid-out MKMapView lands at a broken
        /// zoom — this was exactly the fullscreen-cover bug). If the frame
        /// isn't ready, retry shortly; SwiftUI gives no post-layout callback
        /// for representables.
        func applyInitialCameraIfNeeded(_ map: MKMapView, glow: MKMultiPolyline?, initialRegion: MKCoordinateRegion?) {
            guard !didSetInitialCamera else { return }
            let dataRect = glow?.boundingMapRect ?? .null
            let hasData = initialRegion != nil || (!dataRect.isNull && dataRect.width > 0)
            guard hasData else { return }

            guard map.frame.width > 0 else {
                if !cameraRetryScheduled {
                    cameraRetryScheduled = true
                    Task { @MainActor [weak self, weak map] in
                        try? await Task.sleep(nanoseconds: 80_000_000)
                        guard let self, let map else { return }
                        self.cameraRetryScheduled = false
                        self.applyInitialCameraIfNeeded(map, glow: glow, initialRegion: initialRegion)
                    }
                }
                return
            }

            didSetInitialCamera = true
            if let initialRegion {
                map.setRegion(initialRegion, animated: false)
            } else {
                map.setVisibleMapRect(
                    dataRect,
                    edgePadding: UIEdgeInsets(top: 160, left: 40, bottom: 180, right: 40),
                    animated: false
                )
            }
        }

        /// Fullscreen → main return: apply each distinct handoff exactly once.
        func applyHandoffIfNeeded(_ map: MKMapView, handoffRegion: MKCoordinateRegion?) {
            guard let handoffRegion, map.frame.width > 0 else { return }
            if let applied = appliedHandoff, applied.isApproximately(handoffRegion) { return }
            appliedHandoff = handoffRegion
            map.setRegion(handoffRegion, animated: false)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let glow = overlay as? MKMultiPolyline {
                return TerritoryGlowRenderer(glow: glow)
            }
            if let segment = overlay as? SpeedGradientPolyline {
                let renderer = MKGradientPolylineRenderer(polyline: segment)
                renderer.setColors(segment.gradientColors, locations: segment.gradientLocations)
                renderer.lineWidth = 3.7
                renderer.lineCap = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is CityDotAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: CityDotView.reuseID)
                ?? CityDotView(annotation: annotation, reuseIdentifier: CityDotView.reuseID)
            view.annotation = annotation
            return view
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            onCameraSettled?(mapView.region)
        }
    }
}

extension MKCoordinateRegion {
    /// Loose equality for one-shot camera commands (MKCoordinateRegion isn't
    /// Equatable and exact float comparison would misfire after MapKit's
    /// span normalization).
    func isApproximately(_ other: MKCoordinateRegion) -> Bool {
        abs(center.latitude - other.center.latitude) < 0.0001 &&
        abs(center.longitude - other.center.longitude) < 0.0001 &&
        abs(span.latitudeDelta - other.span.latitudeDelta) < 0.001 &&
        abs(span.longitudeDelta - other.span.longitudeDelta) < 0.001
    }
}

/// The three layer modes of the memory map. Only «Всё» is mocked in Figma;
/// Маршруты = gradient routes only, Территория = amber glow only.
enum MyMapMode: String, CaseIterable {
    case routes, territory, all

    var showsRoutes: Bool { self != .territory }
    var showsTerritory: Bool { self != .routes }

    func title(_ lang: LanguageManager.Language) -> String {
        switch self {
        case .routes:    return AppStrings.mapModeRoutes(lang)
        case .territory: return AppStrings.mapModeTerritory(lang)
        case .all:       return AppStrings.mapModeAll(lang)
        }
    }
}
