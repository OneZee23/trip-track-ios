import Foundation
import CoreData
import CoreLocation

final class RoadCollectionManager {
    private let persistenceController: PersistenceController

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    // MARK: - Process Trip

    /// Call after trip is completed. Returns road info for the completion screen.
    func processTrip(_ trip: Trip) -> RoadCompletionInfo? {
        guard trip.trackPoints.count >= 2 else { return nil }

        let fingerprint = computeGeohashFingerprint(trackPoints: trip.trackPoints)
        guard fingerprint.count >= 2 else { return nil }

        let startHash = fingerprint.first!
        let endHash = fingerprint.last!

        // Try to match existing road
        if let existingRoad = findMatchingRoad(startHash: startHash, endHash: endHash, fingerprint: fingerprint) {
            // Update existing road
            existingRoad.timesDriven += 1
            existingRoad.lastDriven = Date()
            let newLevel = RoadLevel.from(timesDriven: Int(existingRoad.timesDriven))
            existingRoad.level = Int32(newLevel.rawValue)
            persistenceController.save()

            return RoadCompletionInfo(
                name: existingRoad.name ?? formatRoadName(trip: trip),
                rarity: RoadRarity(rawValue: existingRoad.rarity ?? "common") ?? .common,
                level: newLevel,
                timesDriven: Int(existingRoad.timesDriven),
                isNew: false
            )
        }

        // Create new road
        let context = persistenceController.container.viewContext
        let entity = RoadEntity(context: context)
        entity.id = UUID()
        entity.startGeohash = startHash
        entity.endGeohash = endHash
        entity.geohashSequence = fingerprint.joined(separator: ",")
        entity.distanceKm = trip.distanceKm
        entity.timesDriven = 1
        let rarity = RoadRarity.from(distanceKm: trip.distanceKm)
        entity.rarity = rarity.rawValue
        entity.level = Int32(RoadLevel.discovered.rawValue)
        entity.firstDriven = Date()
        entity.lastDriven = Date()

        // Name from trip title or geocode
        let name = formatRoadName(trip: trip)
        entity.name = name

        persistenceController.save()

        return RoadCompletionInfo(
            name: name,
            rarity: rarity,
            level: .discovered,
            timesDriven: 1,
            isNew: true
        )
    }

    // MARK: - Geohash Fingerprint

    /// Compute ordered sequence of unique geohash5 cells for a trip
    func computeGeohashFingerprint(trackPoints: [TrackPoint]) -> [String] {
        var sequence: [String] = []
        var lastHash = ""

        for point in trackPoints {
            let hash = GeohashEncoder.encode(
                latitude: point.latitude,
                longitude: point.longitude,
                precision: 5
            )
            // Skip consecutive duplicates
            if hash != lastHash {
                sequence.append(hash)
                lastHash = hash
            }
        }

        return sequence
    }

    // MARK: - Road Matching

    private func findMatchingRoad(startHash: String, endHash: String, fingerprint: [String]) -> RoadEntity? {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<RoadEntity> = RoadEntity.fetchRequest()

        let startNeighbors = Set(GeohashEncoder.neighbors(of: startHash) + [startHash])
        let endNeighbors = Set(GeohashEncoder.neighbors(of: endHash) + [endHash])
        let allHashes = Array(startNeighbors.union(endNeighbors))

        // Filter at CoreData level to avoid loading all roads
        request.predicate = NSPredicate(
            format: "startGeohash IN %@ OR endGeohash IN %@",
            allHashes, allHashes
        )

        guard let roads = try? context.fetch(request) else { return nil }

        let candidates = roads.filter { road in
            guard let roadStart = road.startGeohash, let roadEnd = road.endGeohash else { return false }
            // Check both directions (A→B or B→A)
            let forwardMatch = startNeighbors.contains(roadStart) && endNeighbors.contains(roadEnd)
            let reverseMatch = startNeighbors.contains(roadEnd) && endNeighbors.contains(roadStart)
            return forwardMatch || reverseMatch
        }

        let fingerprintSet = Set(fingerprint)

        for candidate in candidates {
            guard let seqString = candidate.geohashSequence else { continue }
            let candidateSet = Set(seqString.split(separator: ",").map(String.init))

            // Jaccard similarity
            let intersection = fingerprintSet.intersection(candidateSet)
            let union = fingerprintSet.union(candidateSet)
            let similarity = union.isEmpty ? 0 : Double(intersection.count) / Double(union.count)

            if similarity >= 0.7 {
                return candidate
            }
        }

        return nil
    }

    // MARK: - Road Name

    private func formatRoadName(trip: Trip) -> String {
        if let title = trip.title, !title.isEmpty {
            return title
        }

        // Fallback: start → end from track points
        guard let first = trip.trackPoints.first, let last = trip.trackPoints.last else {
            return "Road"
        }

        let startHash = GeohashEncoder.encode(latitude: first.latitude, longitude: first.longitude, precision: 4)
        let endHash = GeohashEncoder.encode(latitude: last.latitude, longitude: last.longitude, precision: 4)

        if startHash == endHash {
            return trip.region ?? "Loop"
        }

        return trip.region ?? "\(startHash) → \(endHash)"
    }

    // MARK: - Fetch Roads

    func fetchRoads() -> [RoadCard] {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<RoadEntity> = RoadEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \RoadEntity.lastDriven, ascending: false)]

        guard let entities = try? context.fetch(request) else { return [] }

        return entities.compactMap { entity in
            guard let id = entity.id else { return nil }
            let sequence = (entity.geohashSequence ?? "").split(separator: ",").map(String.init)
            return RoadCard(
                id: id,
                name: entity.name ?? "Road",
                rarity: RoadRarity(rawValue: entity.rarity ?? "common") ?? .common,
                level: RoadLevel(rawValue: Int(entity.level)) ?? .discovered,
                timesDriven: Int(entity.timesDriven),
                distanceKm: entity.distanceKm,
                geohashSequence: sequence,
                firstDriven: entity.firstDriven ?? Date(),
                lastDriven: entity.lastDriven ?? Date()
            )
        }
    }
}
