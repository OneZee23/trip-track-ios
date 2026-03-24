import Foundation
import CoreData
import CoreLocation

final class TerritoryManager: ObservableObject {
    @Published var visitedTileCount: Int = 0

    private let persistenceController: PersistenceController
    private var visitedCache: Set<String> = []
    private static let backfillKey = "territory_backfill_done"

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
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
    func getExploration(from trips: [Trip]) -> [ExplorationPlace] {
        guard !visitedCache.isEmpty else { return [] }

        // 1. Map each trip's tiles to its geocoded city/region
        var cityTiles: [String: Set<String>] = [:]  // city -> set of hash6
        var regionTiles: [String: Set<String>] = [:] // region -> set of hash6
        var cityToRegion: [String: String] = [:]     // city -> region mapping
        var unmatchedTiles = visitedCache

        for trip in trips {
            guard !trip.trackPoints.isEmpty else { continue }

            let city = extractCity(from: trip)
            let region = trip.region

            for point in trip.trackPoints {
                let hash6 = GeohashEncoder.encode(
                    latitude: point.latitude,
                    longitude: point.longitude,
                    precision: 6
                )
                guard visitedCache.contains(hash6) else { continue }

                if let city {
                    cityTiles[city, default: []].insert(hash6)
                    unmatchedTiles.remove(hash6)
                    if let region { cityToRegion[city] = region }
                }
                if let region {
                    regionTiles[region, default: []].insert(hash6)
                    unmatchedTiles.remove(hash6)
                }
            }
        }

        // Tiles from trips without a city name but with a region —
        // try to assign to the dominant city in that region
        // (so they don't get lost)

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
                region: cityToRegion[city]
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
                region: nil
            ))
        }

        return places
    }

    private func extractCity(from trip: Trip) -> String? {
        guard let title = trip.title, !title.isEmpty else { return nil }

        // Skip date-format titles like "18 Mar, 21:08" — they aren't city names
        if title.contains(":") && title.count < 20 {
            return nil
        }
        // Skip titles that start with a digit (likely a date)
        if let first = title.first, first.isNumber {
            return nil
        }

        // "Krasnodar → Sochi" → "Krasnodar"
        if let arrow = title.range(of: " → ") {
            return String(title[..<arrow.lowerBound])
        }

        return title
    }

    // MARK: - Backfill from existing trips

    func backfillIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.backfillKey) else { return }

        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TrackPointEntity> = TrackPointEntity.fetchRequest()
        request.fetchBatchSize = 500
        request.propertiesToFetch = ["latitude", "longitude", "timestamp"]

        guard let points = try? context.fetch(request), !points.isEmpty else {
            UserDefaults.standard.set(true, forKey: Self.backfillKey)
            return
        }

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
        UserDefaults.standard.set(true, forKey: Self.backfillKey)
    }

    // MARK: - Stats

    var explorationPercentage: Double {
        min(1.0, Double(visitedTileCount) / 10_000.0)
    }

    var visitedGeohashes: Set<String> {
        visitedCache
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

    enum PlaceType {
        case city
        case region
    }
}
