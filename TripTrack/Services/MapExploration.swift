import Foundation
import CoreLocation

/// Everything the «Моя карта» screen draws and states, derived once from the
/// trips, the visited geohash tiles and the bundled `RegionAtlas`.
///
/// Pure value types built off the main actor: the screen never computes,
/// it only renders what lands here.
struct MapExploration {
    var regions: [MapRegionStat] = []
    var trips: [MapTripPin] = []
    var totalKm: Double = 0
    /// The driven network, collapsed into heat tiers — the map's main layer.
    var fog = RoadFog()

    var isEmpty: Bool { trips.isEmpty }
    var tripCount: Int { trips.count }
    var regionCount: Int { regions.count }
    /// Countries you have driven in, most-driven first — the far-zoom chips.
    var countryCodes: [String] {
        var km: [String: Double] = [:]
        for region in regions { km[region.countryCode, default: 0] += region.km }
        return km.sorted { $0.value > $1.value }.map(\.key)
    }

    func region(id: String) -> MapRegionStat? { regions.first { $0.id == id } }
    func trip(id: UUID) -> MapTripPin? { trips.first { $0.id == id } }
}

/// One opened region: what you drove there, which of its cities you have
/// touched, and how much of it is still dark.
struct MapRegionStat: Identifiable, Equatable {
    let id: String
    let countryCode: String
    let nameRu: String
    let nameEn: String
    let km: Double
    let tripIds: [UUID]
    /// Cities of this region that you have actually been to, best-covered
    /// first. `totalCities` is the region's whole list — the «9 из 44».
    let cities: [MapCityStat]
    let totalCities: Int
    let openedTiles: Int
    /// Length of distinct road opened here — «Дороги края». Counts each
    /// ~150 m cell once no matter how often you drove it, so it grows only
    /// when you go somewhere new.
    let openedRoadKm: Double
    let center: CLLocationCoordinate2D
    let bounds: GeoBounds

    var tripCount: Int { tripIds.count }
    var visitedCityCount: Int { cities.count }

    /// «Дороги края» — opened road against a stated per-region goal. There is
    /// no road-network dataset to divide by, so the bar is progress toward a
    /// goal rather than a share of all roads, and the card prints the real
    /// kilometres next to it so the number never pretends to be something
    /// it isn't.
    var progress: Double {
        min(1, openedRoadKm / MapExploration.roadGoalKm)
    }

    func localizedName(_ language: LanguageManager.Language) -> String {
        language == .ru ? nameRu : nameEn
    }

    static func == (lhs: MapRegionStat, rhs: MapRegionStat) -> Bool {
        lhs.id == rhs.id && lhs.km == rhs.km && lhs.tripIds == rhs.tripIds
            && lhs.openedTiles == rhs.openedTiles && lhs.cities == rhs.cities
            && lhs.openedRoadKm == rhs.openedRoadKm
    }
}

/// A city inside a region. `coverage` is honest area coverage: how many of
/// the tiles in the city's own disc you have driven through.
struct MapCityStat: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let nameEn: String
    let coordinate: CLLocationCoordinate2D
    let coverage: Double

    func localizedName(_ language: LanguageManager.Language) -> String {
        language == .ru ? name : nameEn
    }

    static func == (lhs: MapCityStat, rhs: MapCityStat) -> Bool {
        lhs.name == rhs.name && abs(lhs.coverage - rhs.coverage) < 0.001
    }
}

/// A trip as the map knows it: one pin, one row, one preview card.
struct MapTripPin: Identifiable, Equatable {
    let id: UUID
    /// Where the pin sits — the middle of the route, so two trips from the
    /// same driveway do not stack on top of each other.
    let coordinate: CLLocationCoordinate2D
    let route: [CLLocationCoordinate2D]
    let title: String?
    let startDate: Date
    let distanceKm: Double
    let duration: TimeInterval
    let avgSpeedKmh: Double
    let maxSpeedKmh: Double
    let photoFilename: String?
    let regionId: String?

    static func == (lhs: MapTripPin, rhs: MapTripPin) -> Bool { lhs.id == rhs.id }
}

// MARK: - Builder

extension MapExploration {
    /// km² per precision-6 geohash tile.
    static let km2PerTile = 0.72
    /// «Region opened» goal, in tiles (≈3 600 km²).
    static let regionTileTarget = 5_000
    /// Per-region goal for opened road, in km.
    static let roadGoalKm: Double = 1_000

    /// Build the whole screen model. Runs off the main actor — pass in data
    /// already fetched from CoreData.
    static func build(
        trips: [Trip],
        visitedHashes: Set<String>,
        atlas: RegionAtlas
    ) -> MapExploration {
        var kmByRegion: [Int: Double] = [:]
        var tripIdsByRegion: [Int: [UUID]] = [:]
        var pins: [MapTripPin] = []
        var totalKm: Double = 0
        var routes: [(id: UUID, coordinates: [CLLocationCoordinate2D])] = []
        // Reused across trips instead of reallocated — this is the hot loop.
        var metresHere: [Int: Double] = [:]

        for trip in trips {
            // The preview polyline, not the raw track: it is RDP-simplified
            // from the same drive, faithful to well within the distance to any
            // region border, and it is what the map draws. Loading every track
            // point of every trip just to attribute kilometres cost seconds on
            // the main actor and bought nothing.
            let coords = trip.previewCoordinates
            guard coords.count >= 2 else { continue }

            var homeRegion: Int?
            var lastIndex: Int?
            var pathMetres: Double = 0
            metresHere.removeAll(keepingCapacity: true)

            for i in 1..<coords.count {
                let a = coords[i - 1], b = coords[i]
                let metres = GeometryUtils.haversineDistance(a, b)
                // A jump this long is a GPS glitch or a gap between two
                // stretches of a paused recording, not driving. Counting it
                // would credit a region you flew over.
                guard metres < 20_000 else { lastIndex = nil; continue }

                let mid = CLLocationCoordinate2D(
                    latitude: (a.latitude + b.latitude) / 2,
                    longitude: (a.longitude + b.longitude) / 2
                )
                // Consecutive points almost always share a region, so try the
                // previous answer before searching the atlas.
                var index: Int?
                if let lastIndex, atlas.regionAtIndex(lastIndex, contains: mid) {
                    index = lastIndex
                } else {
                    index = atlas.regionIndex(containing: mid)
                }
                lastIndex = index

                guard let index else { continue }
                pathMetres += metres
                metresHere[index, default: 0] += metres
                if homeRegion == nil { homeRegion = index }
            }

            // Split the trip's REAL distance between its regions in the
            // proportion the path spent in each. Summing simplified segments
            // directly would quietly under-count every bend in the road.
            if pathMetres > 0 {
                let realMetres = trip.distanceKm * 1000
                for (index, metres) in metresHere {
                    kmByRegion[index, default: 0] += realMetres * (metres / pathMetres)
                    tripIdsByRegion[index, default: []].append(trip.id)
                }
            }

            totalKm += trip.distanceKm
            routes.append((trip.id, coords))
            pins.append(MapTripPin(
                id: trip.id,
                coordinate: coords[coords.count / 2],
                route: coords,
                title: trip.title,
                startDate: trip.startDate,
                distanceKm: trip.distanceKm,
                duration: trip.duration,
                avgSpeedKmh: trip.averageSpeedKmh,
                maxSpeedKmh: trip.maxSpeedKmh,
                photoFilename: trip.photos.first?.filename,
                regionId: homeRegion.map { atlas.regions[$0].id }
            ))
        }

        // The fog is built from the SAME preview polylines the map draws, so
        // what you see lit and what the card counts can never disagree.
        let fog = RoadFog.build(trips: routes) { atlas.regionIndex(containing: $0) }

        // Tiles → regions, and a coarse spatial bucket reused for the city
        // coverage pass below.
        var tilesByRegion: [Int: Int] = [:]
        var tileCells: [Int: [CLLocationCoordinate2D]] = [:]
        // Sorted, because a geohash prefix IS spatial locality: neighbouring
        // tiles end up adjacent, so the previous answer is almost always the
        // right one and the atlas search runs a handful of times instead of
        // once per tile. Matters at 50 000 tiles.
        var lastIndex: Int?
        for hash in visitedHashes.sorted() {
            let coord = GeohashEncoder.centerCoordinate(of: hash)
            tileCells[cellKey(coord), default: []].append(coord)
            var index: Int?
            if let lastIndex, atlas.regionAtIndex(lastIndex, contains: coord) {
                index = lastIndex
            } else {
                index = atlas.regionIndex(containing: coord)
            }
            lastIndex = index
            if let index { tilesByRegion[index, default: 0] += 1 }
        }

        var regions: [MapRegionStat] = []
        for (index, metres) in kmByRegion {
            let region = atlas.regions[index]
            let all = atlas.cities(in: region.id)
            let visited = all.compactMap { city -> MapCityStat? in
                let coverage = cityCoverage(city, tileCells: tileCells)
                guard coverage > 0 else { return nil }
                return MapCityStat(
                    name: city.name, nameEn: city.nameEn,
                    coordinate: city.coordinate, coverage: coverage
                )
            }
            .sorted { $0.coverage > $1.coverage }

            regions.append(MapRegionStat(
                id: region.id,
                countryCode: region.countryCode,
                nameRu: region.nameRu,
                nameEn: region.nameEn,
                km: metres / 1000,
                tripIds: tripIdsByRegion[index] ?? [],
                cities: visited,
                totalCities: all.count,
                openedTiles: tilesByRegion[index] ?? 0,
                openedRoadKm: Double(fog.openedCellsByRegion[index] ?? 0) * RoadFog.cellKm,
                center: region.center,
                bounds: region.bounds
            ))
        }
        regions.sort { $0.km > $1.km }

        return MapExploration(regions: regions, trips: pins, totalKm: totalKm, fog: fog)
    }

    /// Share of the city's disc you have driven through, 0…1. The denominator
    /// is the tile count a full disc of that radius would hold, so the number
    /// means something real rather than being scaled to look good.
    private static func cityCoverage(
        _ city: RegionAtlas.City,
        tileCells: [Int: [CLLocationCoordinate2D]]
    ) -> Double {
        let radius = city.radiusMeters
        let radiusDegrees = radius / 111_000
        let span = Int((radiusDegrees / cellSize).rounded(.up)) + 1
        let baseLat = Int((city.coordinate.latitude / cellSize).rounded(.down))
        let baseLon = Int((city.coordinate.longitude / cellSize).rounded(.down))

        var hits = 0
        for dLat in -span...span {
            for dLon in -span...span {
                guard let bucket = tileCells[(baseLat + dLat) &* 10_000 &+ (baseLon + dLon)] else { continue }
                for coord in bucket
                where GeometryUtils.haversineDistance(coord, city.coordinate) <= radius {
                    hits += 1
                }
            }
        }
        guard hits > 0 else { return 0 }
        let discTiles = (.pi * pow(radius / 1000, 2)) / km2PerTile
        return min(1, Double(hits) / max(discTiles, 1))
    }

    private static let cellSize = 0.25

    private static func cellKey(_ coord: CLLocationCoordinate2D) -> Int {
        let la = Int((coord.latitude / cellSize).rounded(.down))
        let lo = Int((coord.longitude / cellSize).rounded(.down))
        return la &* 10_000 &+ lo
    }
}
