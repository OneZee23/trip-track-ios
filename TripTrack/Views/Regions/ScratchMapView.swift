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
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        mapView.overrideUserInterfaceStyle = isDark ? .dark : .light

        let hashesChanged = coordinator.lastGeohashes == nil || visitedGeohashes != coordinator.lastGeohashes

        if hashesChanged {
            // Remove all old overlays
            mapView.removeOverlays(mapView.overlays)

            // Add fog polygon first (renders below polylines)
            if let fog = FogPolygonBuilder.build(visitedHashes: visitedGeohashes, visibleRect: mapView.visibleMapRect.isNull ? .world : mapView.visibleMapRect) {
                mapView.addOverlay(fog, level: .aboveRoads)
            }

            // Add trip route polylines on top
            for poly in tripPolylines {
                mapView.addOverlay(poly, level: .aboveRoads)
            }
            coordinator.lastGeohashes = visitedGeohashes

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
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, MKMapViewDelegate {
        var lastGeohashes: Set<String>?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is FogPolygon {
                let renderer = MKPolygonRenderer(overlay: overlay)
                renderer.fillColor = FogPolygonBuilder.fogColor
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
