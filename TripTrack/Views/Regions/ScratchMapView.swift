import SwiftUI
import MapKit

struct ScratchMapView: UIViewRepresentable {
    let visitedGeohashes: Set<String>
    let tripPolylines: [MKPolyline]
    var isDark: Bool = false

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        mapView.alpha = 0 // Start hidden, fade in after fog renders
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        mapView.overrideUserInterfaceStyle = isDark ? .dark : .light

        let hashesChanged = coordinator.lastGeohashes == nil || visitedGeohashes != coordinator.lastGeohashes
        let themeChanged = coordinator.isDark != isDark
        coordinator.isDark = isDark

        if hashesChanged {
            // Remove old overlays
            if let oldFog = coordinator.currentFogOverlay {
                mapView.removeOverlay(oldFog)
            }
            for poly in coordinator.currentPolylines {
                mapView.removeOverlay(poly)
            }

            // Add trip route polylines
            for poly in tripPolylines {
                mapView.addOverlay(poly, level: .aboveRoads)
            }
            coordinator.currentPolylines = tripPolylines

            // Generate geohash-based reveal mask
            let hashes = visitedGeohashes
            let dark = isDark
            coordinator.lastGeohashes = hashes
            coordinator.fogGenerationToken &+= 1
            let currentToken = coordinator.fogGenerationToken

            DispatchQueue.global(qos: .userInitiated).async {
                let result = FogMaskGenerator.generateCached(geohashes: hashes)
                DispatchQueue.main.async {
                    // Discard stale result if a newer generation was requested
                    guard coordinator.fogGenerationToken == currentToken else { return }

                    if let stale = coordinator.currentFogOverlay {
                        mapView.removeOverlay(stale)
                    }
                    let fog = FogOverlay(
                        revealMask: result?.image,
                        imageMapRect: result?.mapRect ?? .world
                    )
                    let renderer = FogOverlayRenderer(overlay: fog)
                    renderer.isDark = dark
                    coordinator.currentFogRenderer = renderer
                    coordinator.currentFogOverlay = fog
                    mapView.addOverlay(fog, level: .aboveLabels)

                    // Wait for MapKit to render fog tiles, then fade in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseOut) {
                            mapView.alpha = 1
                        }
                    }
                }
            }

            // Center on user location with ~150 km visible span;
            // fall back to bounding box of visited tiles if location unavailable.
            if let userLoc = mapView.userLocation.location,
               userLoc.horizontalAccuracy >= 0 {
                let region = MKCoordinateRegion(
                    center: userLoc.coordinate,
                    latitudinalMeters: 150_000,
                    longitudinalMeters: 150_000
                )
                mapView.setRegion(region, animated: false)
            } else if !visitedGeohashes.isEmpty {
                var unionRect = MKMapRect.null
                for hash in visitedGeohashes {
                    let center = GeohashEncoder.centerCoordinate(of: hash)
                    let point = MKMapPoint(center)
                    let pointRect = MKMapRect(origin: point, size: MKMapSize(width: 1, height: 1))
                    unionRect = unionRect.union(pointRect)
                }
                let expandedRect = unionRect.insetBy(
                    dx: -unionRect.size.width * 0.15,
                    dy: -unionRect.size.height * 0.15
                )
                let insets = UIEdgeInsets(top: 40, left: 20, bottom: 40, right: 20)
                mapView.setVisibleMapRect(expandedRect, edgePadding: insets, animated: false)
            }
        } else if themeChanged {
            if let fog = coordinator.currentFogOverlay {
                mapView.removeOverlay(fog)
                let renderer = FogOverlayRenderer(overlay: fog)
                renderer.isDark = isDark
                coordinator.currentFogRenderer = renderer
                mapView.addOverlay(fog, level: .aboveLabels)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, MKMapViewDelegate {
        var isDark: Bool = false
        var currentFogOverlay: FogOverlay?
        var currentFogRenderer: FogOverlayRenderer?
        var currentPolylines: [MKPolyline] = []
        var lastGeohashes: Set<String>? = nil // nil = never loaded, forces first update
        var fogGenerationToken: UInt = 0

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let fog = overlay as? FogOverlay {
                if let cached = currentFogRenderer, cached.overlay === fog {
                    return cached
                }
                let renderer = FogOverlayRenderer(overlay: fog)
                renderer.isDark = isDark
                currentFogRenderer = renderer
                return renderer
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 235/255, green: 87/255, blue: 30/255, alpha: 0.6)
                renderer.lineWidth = 3
                renderer.lineCap = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
