import Foundation
import CoreData
import CoreLocation

final class TerritoryManager: ObservableObject {
    @Published var visitedTileCount: Int = 0

    private let persistenceController: PersistenceController
    private var visitedCache: Set<String> = []
    /// Internal, not private — see `BackfillLatchTests`.
    static let backfillKey = "territory_backfill_done"

    private let defaults: UserDefaults

    init(persistenceController: PersistenceController = .shared,
         defaults: UserDefaults = .standard) {
        self.persistenceController = persistenceController
        self.defaults = defaults
        loadCache()
    }

    // MARK: - Cache Management

    private func loadCache() {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VisitedGeohashEntity> = VisitedGeohashEntity.fetchRequest()

        if let entities = try? context.fetch(request) {
            visitedCache = Set(entities.compactMap(\.hash6))
            visitedTileCount = visitedCache.count
        }
    }

    // MARK: - Record Visit

    @discardableResult
    func recordVisit(coordinate: CLLocationCoordinate2D) -> Bool {
        let hash6 = GeohashEncoder.encode(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            precision: 6
        )

        if visitedCache.contains(hash6) {
            return false
        }

        visitedCache.insert(hash6)
        visitedTileCount = visitedCache.count

        let context = persistenceController.container.viewContext
        let entity = VisitedGeohashEntity(context: context)
        entity.hash6 = hash6
        entity.firstVisited = Date()
        entity.lastVisited = Date()
        entity.visitCount = 1

        return true
    }

    // MARK: - Exploration Data (from trips)

    /// Build exploration data using trip geocoded info.
    /// Returns city-level + region-level exploration cards.
    ///
    /// City tiles: only track points within ~15 km of the trip start/end
    /// are attributed to the departure/destination city. Highway points
    /// between cities are not counted for any city (but still count for
    /// the region).
    func getExploration(from trips: [Trip]) -> [ExplorationPlace] {
        guard !visitedCache.isEmpty else { return [] }

        let cityRadiusMeters: Double = 15_000

        // 1. Map each trip's tiles to its geocoded city/region
        var cityTiles: [String: Set<String>] = [:]  // city -> set of hash6
        var regionTiles: [String: Set<String>] = [:] // region -> set of hash6
        var cityToRegion: [String: String] = [:]     // city -> region mapping
        var unmatchedTiles = visitedCache
        // Running coordinate accumulators per place — piggyback on the same
        // per-point loop so centroid/bounds cost no extra pass. Density-
        // weighted centroid (per matched point, not per tile) is what the
        // 0.6.0 My-Map card wants: it lands where the activity actually is.
        var cityGeo: [String: GeoAccumulator] = [:]
        var regionGeo: [String: GeoAccumulator] = [:]

        for trip in trips {
            guard !trip.trackPoints.isEmpty else { continue }

            let cities = extractCities(from: trip)
            let region = trip.region

            guard let startPoint = trip.trackPoints.first,
                  let endPoint = trip.trackPoints.last else { continue }
            let startCoord = startPoint.coordinate
            let endCoord = endPoint.coordinate

            for point in trip.trackPoints {
                let hash6 = GeohashEncoder.encode(
                    latitude: point.latitude,
                    longitude: point.longitude,
                    precision: 6
                )
                guard visitedCache.contains(hash6) else { continue }

                let pointCoord = point.coordinate

                if let startCity = cities.start,
                   GeometryUtils.haversineDistance(pointCoord, startCoord) <= cityRadiusMeters {
                    cityTiles[startCity, default: []].insert(hash6)
                    unmatchedTiles.remove(hash6)
                    if let region { cityToRegion[startCity] = region }
                    cityGeo[startCity, default: GeoAccumulator()].add(pointCoord)
                }

                if let endCity = cities.end, endCity != cities.start,
                   GeometryUtils.haversineDistance(pointCoord, endCoord) <= cityRadiusMeters {
                    cityTiles[endCity, default: []].insert(hash6)
                    unmatchedTiles.remove(hash6)
                    if let region { cityToRegion[endCity] = region }
                    cityGeo[endCity, default: GeoAccumulator()].add(pointCoord)
                }

                if let region {
                    regionTiles[region, default: []].insert(hash6)
                    unmatchedTiles.remove(hash6)
                    regionGeo[region, default: GeoAccumulator()].add(pointCoord)
                }
            }
        }

        // 2. Build city cards
        var places: [ExplorationPlace] = []

        // Geohash6 tile ≈ 0.72 km²
        // City target: ~500 tiles ≈ 360 km² (covers most cities)
        // Region target: ~5000 tiles ≈ 3600 km² (reasonable for a state/province)
        let cityTarget = 500
        let regionTarget = 5000

        for (city, tiles) in cityTiles.sorted(by: { $0.value.count > $1.value.count }) {
            let percentage = min(1.0, Double(tiles.count) / Double(cityTarget))
            places.append(ExplorationPlace(
                name: city,
                type: .city,
                tileCount: tiles.count,
                target: cityTarget,
                percentage: percentage,
                status: ZoneStatus.from(percentage: percentage),
                region: cityToRegion[city],
                centroid: cityGeo[city]?.centroid,
                bounds: cityGeo[city]?.bounds
            ))
        }

        // 3. Build region cards
        for (region, tiles) in regionTiles.sorted(by: { $0.value.count > $1.value.count }) {
            let percentage = min(1.0, Double(tiles.count) / Double(regionTarget))
            places.append(ExplorationPlace(
                name: region,
                type: .region,
                tileCount: tiles.count,
                target: regionTarget,
                percentage: percentage,
                status: ZoneStatus.from(percentage: percentage),
                region: nil,
                centroid: regionGeo[region]?.centroid,
                bounds: regionGeo[region]?.bounds
            ))
        }

        return places
    }

    /// Look up start and end city names from the geocode cache using trip coordinates.
    /// Falls back to parsing trip title if cache misses.
    private func extractCities(from trip: Trip) -> (start: String?, end: String?) {
        guard !trip.trackPoints.isEmpty else { return (nil, nil) }

        let context = persistenceController.container.viewContext

        // Try geocode cache first (most reliable — uses same data as trip naming)
        func cachedLocality(for coord: CLLocationCoordinate2D) -> String? {
            let geohash5 = GeohashEncoder.encode(latitude: coord.latitude, longitude: coord.longitude, precision: 5)
            let request: NSFetchRequest<GeocodeCacheEntity> = GeocodeCacheEntity.fetchRequest()
            request.predicate = NSPredicate(format: "geohash5 == %@", geohash5)
            request.fetchLimit = 1
            return (try? context.fetch(request).first)?.locality
        }

        let startCity = trip.trackPoints.first.flatMap { cachedLocality(for: $0.coordinate) }
        let endCity = trip.trackPoints.last.flatMap { cachedLocality(for: $0.coordinate) }

        if startCity != nil || endCity != nil {
            let effectiveEnd = (endCity != startCity) ? endCity : nil
            return (startCity, effectiveEnd)
        }

        // Fallback: parse trip title
        guard let title = trip.title, !title.isEmpty else { return (nil, nil) }
        if title.contains(":") && title.count < 20 { return (nil, nil) }
        if let first = title.first, first.isNumber { return (nil, nil) }

        if let arrow = title.range(of: " → ") {
            let start = String(title[..<arrow.lowerBound])
            let end = String(title[arrow.upperBound...])
            return (start, end.isEmpty ? nil : end)
        }

        return (title, nil)
    }

    // MARK: - Rebuild (after trip deletion)

    /// Rebuilds visited geohashes from all active trips' track points on a background context.
    func rebuildFromTrips() {
        let pc = persistenceController
        let bgContext = pc.container.newBackgroundContext()

        bgContext.perform {
            let existing: NSFetchRequest<VisitedGeohashEntity> = VisitedGeohashEntity.fetchRequest()
            if let entities = try? bgContext.fetch(existing) {
                for entity in entities { bgContext.delete(entity) }
            }

            let request = NSFetchRequest<NSFetchRequestResult>(entityName: "TrackPointEntity")
            request.predicate = NSPredicate(format: "trip.endDate != nil AND trip.syncStatus != %d", SyncStatus.pendingDelete.rawValue)
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["latitude", "longitude"]
            request.fetchBatchSize = 500

            var newHashes = Set<String>()
            if let results = try? bgContext.fetch(request) as? [[String: Any]] {
                for dict in results {
                    guard let lat = dict["latitude"] as? Double,
                          let lon = dict["longitude"] as? Double else { continue }
                    newHashes.insert(GeohashEncoder.encode(latitude: lat, longitude: lon, precision: 6))
                }
            }

            let now = Date()
            for hash in newHashes {
                let entity = VisitedGeohashEntity(context: bgContext)
                entity.hash6 = hash
                entity.firstVisited = now
                entity.lastVisited = now
                entity.visitCount = 1
            }
            try? bgContext.save()

            Task { @MainActor [weak self] in
                self?.visitedCache = newHashes
                self?.visitedTileCount = newHashes.count
                FogPolygonBuilder.clearCache()
                NotificationCenter.default.post(name: .territoryRebuilt, object: nil)
            }
        }
    }

    // MARK: - Backfill from existing trips

    func backfillIfNeeded() {
        guard !defaults.bool(forKey: Self.backfillKey) else { return }

        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TrackPointEntity> = TrackPointEntity.fetchRequest()
        request.fetchBatchSize = 500
        request.propertiesToFetch = ["latitude", "longitude", "timestamp"]

        // No points is not "nothing to do" — on the launch that lost a user's
        // store it meant "the data has not come back yet", and latching there
        // would have kept the fog empty forever. Leave the flag open and let a
        // later launch, after a heal, actually do the work.
        guard let points = try? context.fetch(request), !points.isEmpty else { return }

        var newHashes: [(String, Date)] = []
        for point in points {
            let hash6 = GeohashEncoder.encode(
                latitude: point.latitude,
                longitude: point.longitude,
                precision: 6
            )
            if !visitedCache.contains(hash6) {
                visitedCache.insert(hash6)
                newHashes.append((hash6, point.timestamp ?? Date()))
            }
        }

        let batchSize = 500
        for i in stride(from: 0, to: newHashes.count, by: batchSize) {
            let batch = newHashes[i..<min(i + batchSize, newHashes.count)]
            for (hash, date) in batch {
                let entity = VisitedGeohashEntity(context: context)
                entity.hash6 = hash
                entity.firstVisited = date
                entity.lastVisited = date
                entity.visitCount = 1
            }
            persistenceController.save()
        }

        visitedTileCount = visitedCache.count
        // Latch only after real work.
        defaults.set(true, forKey: Self.backfillKey)
    }

    // MARK: - Stats

    var explorationPercentage: Double {
        min(1.0, Double(visitedTileCount) / 10_000.0)
    }

    var visitedGeohashes: Set<String> {
        visitedCache
    }

    /// Fetch geohash6 strings visited before or on the given date.
    /// Used for temporal fog in trip detail (shows fog state at trip.endDate).
    func visitedHashes(before date: Date) -> Set<String> {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VisitedGeohashEntity> = VisitedGeohashEntity.fetchRequest()
        request.predicate = NSPredicate(format: "firstVisited <= %@", date as NSDate)
        guard let entities = try? context.fetch(request) else { return [] }
        return Set(entities.compactMap(\.hash6))
    }
}

// MARK: - Exploration Place Model

struct ExplorationPlace: Identifiable {
    let id = UUID()
    let name: String
    let type: PlaceType
    let tileCount: Int
    let target: Int
    let percentage: Double
    let status: ZoneStatus
    let region: String? // parent region for cities
    /// Density-weighted center of the place's recorded activity (0.6.0 My Map
    /// uses it for city dots and camera→region resolution). Nil when the
    /// place had no attributable points.
    var centroid: CLLocationCoordinate2D? = nil
    /// Bounding box of the place's attributed points, for camera hit-testing.
    var bounds: GeoBounds? = nil

    enum PlaceType {
        case city
        case region
    }
}

/// MapKit-free lat/lon bounding box (TerritoryManager stays a pure service).
struct GeoBounds {
    var minLat: Double
    var maxLat: Double
    var minLon: Double
    var maxLon: Double

    func contains(_ c: CLLocationCoordinate2D) -> Bool {
        c.latitude >= minLat && c.latitude <= maxLat &&
        c.longitude >= minLon && c.longitude <= maxLon
    }
}

/// Running mean + extremes over coordinates; one instance per place.
struct GeoAccumulator {
    private var latSum = 0.0, lonSum = 0.0
    private var count = 0
    private var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0

    mutating func add(_ c: CLLocationCoordinate2D) {
        latSum += c.latitude; lonSum += c.longitude; count += 1
        minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
        minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
    }

    var centroid: CLLocationCoordinate2D? {
        guard count > 0 else { return nil }
        return CLLocationCoordinate2D(latitude: latSum / Double(count), longitude: lonSum / Double(count))
    }

    var bounds: GeoBounds? {
        guard count > 0 else { return nil }
        return GeoBounds(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
    }
}
