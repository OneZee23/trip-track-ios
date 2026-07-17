import Foundation
import MapKit
import SwiftUI

/// Data source for the 6.1.0 «Моя карта» screen: one amber territory-glow
/// multipolyline, per-trip speed-gradient route segments, city dots and the
/// zoom-morphing stats (absolute totals ↔ focused region card).
///
/// CoreData work (trip fetch, exploration attribution incl. geocode-cache
/// lookups) stays on the main actor — same as the screen it replaces; only
/// the pure-geometry polyline/gradient construction detaches.
@MainActor
final class MyMapViewModel: ObservableObject {
    /// App-scoped singleton: the Maps tab view is destroyed on every tab
    /// switch (ContentView renders tabs in a switch), so a view-owned
    /// @StateObject would re-run the full CoreData + exploration pass on
    /// every visit. The old RegionsView solved this with MapViewModel-hosted
    /// caches; this VM carries its own state instead.
    static let shared = MyMapViewModel()

    struct CityDot: Identifiable {
        let id: String        // city name — stable across reloads
        let coordinate: CLLocationCoordinate2D
    }

    struct RegionStats: Equatable {
        let name: String
        let km2: Int
        let cityCount: Int
        let tripCount: Int
        let bounds: GeoBounds?
        let centroid: CLLocationCoordinate2D?

        static func == (lhs: RegionStats, rhs: RegionStats) -> Bool { lhs.name == rhs.name }
    }

    @Published private(set) var isLoading = true
    @Published private(set) var glow: MKMultiPolyline?
    @Published private(set) var routeSegments: [SpeedGradientPolyline] = []
    @Published private(set) var cityDots: [CityDot] = []
    @Published private(set) var totalKm2 = 0
    @Published private(set) var regionCount = 0
    @Published private(set) var cityCount = 0
    @Published private(set) var regions: [RegionStats] = []
    /// Non-nil while the camera is zoomed into an explored region — drives
    /// the plate → region-card morph.
    @Published var focusedRegion: RegionStats?

    var isEmpty: Bool { !isLoading && routeSegments.isEmpty }

    /// km² per precision-6 geohash tile (same constant the old screen used).
    static let km2PerTile = 0.72
    /// Camera spans wider than this are "zoomed out" → absolute plate.
    static let regionZoomThreshold: CLLocationDegrees = 1.2

    private var loaded = false
    private var stale = false
    private var loadGeneration = 0
    private weak var tripManagerRef: TripManager?
    private weak var territoryRef: TerritoryManager?

    init() {
        // Data changes invalidate the map. When the tab is off-screen the
        // reload happens here directly (the view can't); loadIfNeeded also
        // rechecks `stale` on the next appearance as a belt-and-braces.
        for name: Notification.Name in [.territoryRebuilt, .tripRecordingEnded, .tripDeleted] {
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.stale = true
                    if self.loaded, let tm = self.tripManagerRef, let t = self.territoryRef {
                        await self.reload(tripManager: tm, territory: t)
                    }
                }
            }
        }
    }

    func loadIfNeeded(tripManager: TripManager, territory: TerritoryManager) async {
        guard !loaded || stale else { return }
        loaded = true
        await reload(tripManager: tripManager, territory: territory)
    }

    func reload(tripManager: TripManager, territory: TerritoryManager) async {
        tripManagerRef = tripManager
        territoryRef = territory
        stale = false
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true

        // Main-actor: CoreData fetch + exploration attribution (hits the
        // geocode cache on the view context). The repository's completed-trip
        // predicate already excludes pendingDelete rows.
        let trips = tripManager.fetchTripsWithTrackPoints()
        let places = territory.getExploration(from: trips)
        let tileCount = territory.visitedTileCount

        // Pure geometry — off-main.
        let built = await Task.detached(priority: .userInitiated) {
            Self.buildOverlays(from: trips)
        }.value

        // A newer reload superseded this one while the build was detached.
        guard generation == loadGeneration else { return }

        let cities = places.filter { $0.type == .city }
        let regionPlaces = places.filter { $0.type == .region }
        let tripsByRegion = Dictionary(grouping: trips.compactMap(\.region)) { $0 }
            .mapValues(\.count)

        glow = built.glow
        routeSegments = built.segments
        cityDots = cities.compactMap { place in
            place.centroid.map { CityDot(id: place.name, coordinate: $0) }
        }
        totalKm2 = Int((Double(tileCount) * Self.km2PerTile).rounded())
        regionCount = regionPlaces.count
        cityCount = cities.count
        regions = regionPlaces.map { place in
            RegionStats(
                name: place.name,
                km2: Int((Double(place.tileCount) * Self.km2PerTile).rounded()),
                cityCount: cities.filter { $0.region == place.name }.count,
                tripCount: tripsByRegion[place.name] ?? 0,
                bounds: place.bounds,
                centroid: place.centroid
            )
        }
        isLoading = false
    }

    /// Camera → focused region resolution (called from the map delegate when
    /// panning/zooming settles). Bounding-box hit first, nearest centroid
    /// within ~150 km as fallback.
    func resolveFocusedRegion(for cameraRegion: MKCoordinateRegion) {
        guard cameraRegion.span.latitudeDelta < Self.regionZoomThreshold, !regions.isEmpty else {
            if focusedRegion != nil { withAnimation(.easeInOut(duration: 0.2)) { focusedRegion = nil } }
            return
        }
        let center = cameraRegion.center
        var match = regions.first { $0.bounds?.contains(center) == true }
        if match == nil {
            let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
            match = regions
                .compactMap { region -> (RegionStats, CLLocationDistance)? in
                    guard let c = region.centroid else { return nil }
                    return (region, centerLoc.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)))
                }
                .filter { $0.1 < 150_000 }
                .min { $0.1 < $1.1 }?.0
        }
        if match != focusedRegion {
            withAnimation(.easeInOut(duration: 0.2)) { focusedRegion = match }
        }
    }

    // MARK: - Overlay construction (off-main, value types only)

    private struct BuiltOverlays {
        let glow: MKMultiPolyline
        let segments: [SpeedGradientPolyline]
    }

    /// Figma speed→color stops (My-Map-local palette; thresholds shared with
    /// `SpeedColorScale` so the semantics stay consistent app-wide).
    private nonisolated static func color(forSpeedKmh v: Double) -> UIColor {
        switch v {
        case ..<50:   return UIColor(red: 0x30/255, green: 0xD1/255, blue: 0x58/255, alpha: 1)
        case ..<90:   return UIColor(red: 0xF5/255, green: 0xBE/255, blue: 0x1E/255, alpha: 1)
        case ..<110:  return UIColor(red: 0xEB/255, green: 0x57/255, blue: 0x1E/255, alpha: 1)
        default:      return UIColor(red: 0xFF/255, green: 0x45/255, blue: 0x3A/255, alpha: 1)
        }
    }

    private nonisolated static func buildOverlays(from trips: [Trip]) -> BuiltOverlays {
        var allPolylines: [MKPolyline] = []
        var gradientSegments: [SpeedGradientPolyline] = []

        for trip in trips {
            let coords = trip.previewCoordinates
            guard coords.count >= 2 else { continue }

            // NO gap-splitting here: preview polylines are RDP-simplified, so
            // legitimate straight stretches leave >1km between vertices and a
            // distance-based splitter shreds them to nothing (the exact trap
            // RouteMapView documents for sparse social previews). Real GPS
            // gaps draw as straight connectors — acceptable at 3.7pt widths
            // on a zoomed-out memory map.
            let points = trip.trackPoints
            let speeds: [Double]
            if points.count >= 2 {
                // Proportional-index speed sampling: preview vertex i of m
                // maps to trackpoint round(i/(m-1)·(n-1)).
                let n = points.count, m = coords.count
                speeds = (0..<m).map { i in
                    let idx = Int((Double(i) / Double(m - 1) * Double(n - 1)).rounded())
                    return points[idx].speed * 3.6
                }
            } else {
                speeds = Array(repeating: trip.averageSpeed * 3.6, count: coords.count)
            }

            let poly = SpeedGradientPolyline(coordinates: coords, count: coords.count)
            poly.gradientColors = speeds.map { color(forSpeedKmh: $0) }
            poly.gradientLocations = Self.distanceFractions(coords)
            gradientSegments.append(poly)
            allPolylines.append(MKPolyline(coordinates: coords, count: coords.count))
        }

        return BuiltOverlays(
            glow: MKMultiPolyline(allPolylines),
            segments: gradientSegments
        )
    }

    /// Cumulative-distance fractions (0…1) for gradient stop locations.
    private nonisolated static func distanceFractions(_ coords: [CLLocationCoordinate2D]) -> [CGFloat] {
        guard coords.count >= 2 else { return coords.map { _ in 0 } }
        var cumulative: [Double] = [0]
        for i in 1..<coords.count {
            cumulative.append(cumulative[i - 1] + GeometryUtils.haversineDistance(coords[i - 1], coords[i]))
        }
        let total = max(cumulative.last ?? 1, 1)
        return cumulative.map { CGFloat($0 / total) }
    }
}
