import Foundation
import MapKit
import SwiftUI

/// Data source for the 0.6.0 «Моя карта» screen (Figma page «🧭 Карта»).
///
/// The canon note on that page sets the model: one free-pan map where the
/// territory and the trips live in the SAME layer — «слоёв-переключателей
/// нет» — and everything on it is tappable, with a permanent sheet that
/// swaps its contents to whatever you touched.
///
/// So this VM holds two things: the exploration (built once from CoreData +
/// the bundled `RegionAtlas`) and the current selection, which is what the
/// sheet and the highlighted overlay both read.
@MainActor
final class MyMapViewModel: ObservableObject {
    /// App-scoped singleton: the Maps tab view is destroyed on every tab
    /// switch (ContentView renders tabs in a switch), so a view-owned
    /// @StateObject would re-run the full CoreData + attribution pass on
    /// every visit.
    static let shared = MyMapViewModel()

    /// What the sheet is currently showing. `nil` = the collapsed summary.
    enum Selection: Equatable {
        case region(String)         // atlas region id, opened
        case lockedRegion(String)   // atlas region id, never driven
        case trip(UUID)
        /// Every trip that used the road under your finger, newest first.
        /// A street you drive daily belongs to a dozen trips, and handing back
        /// only the nearest one made the other eleven unreachable.
        case road([UUID])
    }

    @Published private(set) var isLoading = true
    @Published private(set) var exploration = MapExploration()
    /// The driven network as one overlay. Rebuilt only when the data does.
    @Published private(set) var fogOverlay: RoadFogOverlay?
    /// The dark over everywhere the network has not reached — same geometry,
    /// used as a mask instead of as lines.
    @Published private(set) var fogVeil: FogOfWarOverlay?
    /// The one route drawn in full speed-gradient detail — the trip you
    /// selected, and nothing else. Drawing all of them at once is what turned
    /// the map into a green smear; the unified fog carries the network now.
    ///
    /// Built on demand. Colouring it needs per-point speeds, and loading the
    /// track points of every trip up front to colour one line was the single
    /// most expensive thing this screen did.
    @Published private(set) var selectedRoute: SpeedGradientPolyline?
    /// Last few built routes, so flipping between trips does not re-fetch.
    private var routeCache: [UUID: SpeedGradientPolyline] = [:]
    private var routeCacheOrder: [UUID] = []
    private var routeTask: Task<Void, Never>?
    /// Set through `select` / `selectRoad` only — the drawn route is kept in
    /// step from there, and a direct write would leave the two disagreeing.
    @Published private(set) var selection: Selection?
    /// One-shot camera command consumed by the map (`nil` once applied).
    @Published var cameraCommand: MapCameraCommand?

    var isEmpty: Bool { !isLoading && exploration.isEmpty }

    private var loaded = false
    private var stale = false
    private var loadGeneration = 0
    private weak var tripManagerRef: TripManager?
    private weak var territoryRef: TerritoryManager?

    init() {
        // Data changes invalidate the map. When the tab is off-screen the
        // reload happens here directly (the view can't); loadIfNeeded also
        // rechecks `stale` on the next appearance as a belt-and-braces.
        // .syncPullCompleted: restore-on-fresh-device / second-device trips
        // land via Cloud-Sync pull, which touches neither territory nor
        // recording — without it the Maps tab stays empty all session.
        for name: Notification.Name in [.territoryRebuilt, .tripRecordingEnded, .tripDeleted, .syncPullCompleted] {
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
        // Loader only when there is nothing on screen yet. Background
        // refreshes of an already-populated map must not flash over the
        // still-rendered content.
        if exploration.isEmpty { isLoading = true }

        await RegionAtlas.shared.loadIfNeeded()

        // Main-actor: CoreData fetch. Everything after it is pure value work.
        let trips = tripManager.fetchTripsForMap()
        let hashes = territory.visitedGeohashes
        let atlas = RegionAtlas.shared

        let built = await Task.detached(priority: .userInitiated) {
            let exploration = MapExploration.build(trips: trips, visitedHashes: hashes, atlas: atlas)
            // The overlays are built here too: turning the network into
            // MKPolylines is thousands of allocations, and doing it on the
            // main actor stalled the first frame of the map.
            let fog = exploration.fog.isEmpty ? nil : RoadFogOverlay(fog: exploration.fog)
            return (exploration, fog)
        }.value

        // A newer reload superseded this one while the build was detached.
        guard generation == loadGeneration else { return }

        exploration = built.0
        fogOverlay = built.1
        fogVeil = built.1.map { FogOfWarOverlay(fog: $0) }
        // The trips underneath the cached lines may have changed.
        routeCache.removeAll()
        routeCacheOrder.removeAll()
        // Drop a selection whose subject no longer exists (trip deleted on
        // another device, region emptied by a rebuild).
        if let current = selection, resolve(current) == nil { selection = nil }
        refreshSelectedRoute()
        isLoading = false
    }

    // MARK: - Selected route

    /// Keeps `selectedRoute` in step with the selection, fetching the one
    /// trip's track points off the main actor only when it has to.
    private func refreshSelectedRoute() {
        routeTask?.cancel()
        routeTask = nil

        guard case .trip(let id) = selection else {
            selectedRoute = nil
            return
        }
        if let cached = routeCache[id] {
            selectedRoute = cached
            return
        }

        selectedRoute = nil
        guard let manager = tripManagerRef else { return }
        routeTask = Task { [weak self] in
            // One trip's points, not every trip's.
            guard let trip = manager.tripDetail(id: id) else { return }
            let route = await Task.detached(priority: .userInitiated) {
                Self.buildRoute(from: trip)
            }.value
            guard !Task.isCancelled, let self, let route else { return }
            self.cacheRoute(route, for: id)
            if case .trip(id) = self.selection { self.selectedRoute = route }
        }
    }

    private func cacheRoute(_ route: SpeedGradientPolyline, for id: UUID) {
        routeCache[id] = route
        routeCacheOrder.removeAll { $0 == id }
        routeCacheOrder.append(id)
        while routeCacheOrder.count > 8 {
            routeCache.removeValue(forKey: routeCacheOrder.removeFirst())
        }
    }

    // MARK: - Selection

    /// Tap on the map background: open region → region card, anything else
    /// the atlas knows → the locked-region card (canon: «регион (открытый И
    /// закрытый) → автозум + sheet»), sea or unknown → back to the summary.
    func selectRegion(at coordinate: CLLocationCoordinate2D, zoom: Bool = true) {
        guard let region = RegionAtlas.shared.region(containing: coordinate) else {
            select(nil)
            return
        }
        let isOpen = exploration.region(id: region.id) != nil
        select(isOpen ? .region(region.id) : .lockedRegion(region.id), zoom: zoom)
    }

    /// Tap on a road. One trip goes straight to its card; several open the
    /// list, without moving the camera — you are already looking at the road
    /// you asked about.
    func selectRoad(_ tripIds: [UUID]) {
        let byDate = tripIds
            .compactMap { exploration.trip(id: $0) }
            .sorted { $0.startDate > $1.startDate }
            .map(\.id)
        guard let first = byDate.first else { return }
        // Never move the camera on a road tap, not even for a single trip:
        // you pointed at a street, and fitting a 250 km drive to the screen
        // throws you out of the neighbourhood you were reading.
        select(byDate.count == 1 ? .trip(first) : .road(byDate), zoom: false)
    }

    func select(_ new: Selection?, zoom: Bool = true) {
        guard new != selection else { return }
        selection = new
        refreshSelectedRoute()
        guard zoom, let new else { return }
        switch new {
        case .region(let id), .lockedRegion(let id):
            if let region = RegionAtlas.shared.region(id: id) {
                cameraCommand = .fit(region.bounds, padding: .region)
            }
        // A road pick never moves the camera — you are already looking at the
        // road you asked about, and `selectRoad` passes zoom: false anyway.
        case .road:
            break
        case .trip(let id):
            if let pin = exploration.trip(id: id), let bounds = GeoBounds(covering: pin.route) {
                cameraCommand = .fit(bounds, padding: .trip)
            }
        }
    }

    /// Selection → the thing it points at, or nil if it went away.
    private func resolve(_ selection: Selection) -> Any? {
        switch selection {
        case .region(let id):       return exploration.region(id: id)
        case .lockedRegion(let id): return RegionAtlas.shared.region(id: id)
        case .trip(let id):         return exploration.trip(id: id)
        case .road(let ids):        return selectedRoadTrips(ids).isEmpty ? nil : ids
        }
    }

    /// The trips behind a road selection, minus any that have since gone.
    func selectedRoadTrips(_ ids: [UUID]) -> [MapTripPin] {
        ids.compactMap { exploration.trip(id: $0) }
    }

    var selectedRoad: [MapTripPin]? {
        guard case .road(let ids) = selection else { return nil }
        return selectedRoadTrips(ids)
    }

    var selectedRegion: MapRegionStat? {
        guard case .region(let id) = selection else { return nil }
        return exploration.region(id: id)
    }

    var selectedLockedRegion: RegionAtlas.Region? {
        guard case .lockedRegion(let id) = selection else { return nil }
        return RegionAtlas.shared.region(id: id)
    }

    var selectedTrip: MapTripPin? {
        guard case .trip(let id) = selection else { return nil }
        return exploration.trip(id: id)
    }

    /// The region whose border should be traced right now — the selected one,
    /// open or locked.
    var highlightedRegionId: String? {
        switch selection {
        case .region(let id), .lockedRegion(let id): return id
        default: return nil
        }
    }

    // MARK: - Locked-region teaser

    /// «Ближайший твой след — 40 км западнее: Кропоткин, май 2026».
    ///
    /// Measured to the nearest city you have actually opened, because a
    /// distance to a bare coordinate says nothing — the point of the line is
    /// to name a place you remember and make the gap feel crossable.
    struct NearestTrace {
        let distanceKm: Int
        let bearing: Bearing
        let cityName: String
        let date: Date?

        enum Bearing { case north, south, east, west }
    }

    func nearestTrace(to region: RegionAtlas.Region) -> NearestTrace? {
        var best: (city: MapCityStat, regionId: String, metres: Double)?
        let target = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        for stat in exploration.regions {
            for city in stat.cities {
                let metres = target.distance(
                    from: CLLocation(latitude: city.coordinate.latitude, longitude: city.coordinate.longitude)
                )
                if best == nil || metres < best!.metres {
                    best = (city, stat.id, metres)
                }
            }
        }
        guard let best else { return nil }

        // Distance to the region's edge, not to the label in its middle —
        // otherwise a neighbouring region reads as «300 км» when its border
        // is half an hour away.
        let edge = region.bounds.nearestEdgeDistance(from: best.city.coordinate)
        let latestTrip = exploration.trips
            .filter { $0.regionId == best.regionId }
            .max { $0.startDate < $1.startDate }

        // From the REGION towards the trace, not the other way round: the
        // sentence is «твой след — 40 км западнее», so it describes where the
        // trace sits relative to the region you are looking at.
        let dLat = best.city.coordinate.latitude - region.center.latitude
        let dLon = best.city.coordinate.longitude - region.center.longitude
        let bearing: NearestTrace.Bearing
        if abs(dLat) > abs(dLon) * 1.2 {
            bearing = dLat > 0 ? .north : .south
        } else {
            bearing = dLon > 0 ? .east : .west
        }

        return NearestTrace(
            distanceKm: max(1, Int((edge / 1000).rounded())),
            bearing: bearing,
            cityName: best.city.name,
            date: latestTrip?.startDate
        )
    }

    // MARK: - Overlay construction (off-main, value types only)

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

    nonisolated static func buildRoute(from trip: Trip) -> SpeedGradientPolyline? {
        let coords = trip.previewCoordinates
        guard coords.count >= 2 else { return nil }

        // NO gap-splitting here: preview polylines are RDP-simplified, so
        // legitimate straight stretches leave >1km between vertices and a
        // distance-based splitter shreds them to nothing (the exact trap
        // RouteMapView documents for sparse social previews).
        let points = trip.trackPoints
        let speeds: [Double]
        if points.count >= 2 {
            // Proportional-index speed sampling: preview vertex i of m
            // maps to trackpoint round(i/(m-1)·(n-1)).
            let n = points.count, m = coords.count
            speeds = (0..<m).map { i in
                let idx = Int((Double(i) / Double(m - 1) * Double(n - 1)).rounded())
                return points[min(max(idx, 0), n - 1)].speed * 3.6
            }
        } else {
            speeds = Array(repeating: trip.averageSpeed * 3.6, count: coords.count)
        }

        let poly = SpeedGradientPolyline(coordinates: coords, count: coords.count)
        poly.tripId = trip.id
        poly.gradientColors = speeds.map { color(forSpeedKmh: $0) }
        poly.gradientLocations = Self.distanceFractions(coords)
        return poly
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

// MARK: - Camera

/// One-shot camera instructions from the VM to the map view.
enum MapCameraCommand: Equatable {
    case fit(GeoBounds, padding: Padding)

    enum Padding {
        /// Region card is 214 pt tall — leave the region visible above it.
        case region
        /// Trip card is 176 pt.
        case trip

        var insets: UIEdgeInsets {
            switch self {
            case .region: return UIEdgeInsets(top: 130, left: 32, bottom: 250, right: 32)
            case .trip:   return UIEdgeInsets(top: 130, left: 44, bottom: 220, right: 44)
            }
        }
    }
}

extension GeoBounds: Equatable {
    init?(covering coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else { return nil }
        var box = GeoBounds(minLat: 90, maxLat: -90, minLon: 180, maxLon: -180)
        for c in coordinates {
            box.minLat = min(box.minLat, c.latitude)
            box.maxLat = max(box.maxLat, c.latitude)
            box.minLon = min(box.minLon, c.longitude)
            box.maxLon = max(box.maxLon, c.longitude)
        }
        self = box
    }

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
    }

    var mapRect: MKMapRect {
        let a = MKMapPoint(CLLocationCoordinate2D(latitude: maxLat, longitude: minLon))
        let b = MKMapPoint(CLLocationCoordinate2D(latitude: minLat, longitude: maxLon))
        let rect = MKMapRect(x: min(a.x, b.x), y: min(a.y, b.y),
                             width: abs(a.x - b.x), height: abs(a.y - b.y))
        // A trip that never moved — or one point that survived filtering —
        // gives a zero-size rect, and `setVisibleMapRect` answers that by
        // zooming to the tightest level the map has. Give it a block to look
        // at instead.
        let floor = 300 * MKMapPointsPerMeterAtLatitude(center.latitude)
        guard rect.width < floor || rect.height < floor else { return rect }
        return MKMapRect(
            x: rect.midX - max(rect.width, floor) / 2,
            y: rect.midY - max(rect.height, floor) / 2,
            width: max(rect.width, floor),
            height: max(rect.height, floor)
        )
    }

    /// Great-circle distance from a coordinate to the nearest point of the box
    /// (zero when inside).
    func nearestEdgeDistance(from coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        let lat = min(max(coordinate.latitude, minLat), maxLat)
        let lon = min(max(coordinate.longitude, minLon), maxLon)
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: lat, longitude: lon))
    }

    public static func == (lhs: GeoBounds, rhs: GeoBounds) -> Bool {
        lhs.minLat == rhs.minLat && lhs.maxLat == rhs.maxLat
            && lhs.minLon == rhs.minLon && lhs.maxLon == rhs.maxLon
    }
}
