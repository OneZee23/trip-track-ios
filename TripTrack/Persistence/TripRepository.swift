import Foundation
import CoreData
import CoreLocation
import UIKit

// MARK: - Protocol

protocol TripRepository {
    func fetchTrips(limit: Int, offset: Int) -> [Trip]
    func fetchAllTrips() -> [Trip]
    func fetchTripsWithTrackPoints() -> [Trip]
    func fetchTripsModifiedSince(_ date: Date) -> [Trip]
    func fetchTripDetail(id: UUID) -> Trip?
    func fetchTripCount() -> Int
    func fetchLastTripDate() -> Date?
    func fetchTripStats() -> (count: Int, totalDistance: Double)
    func fetchTotalDistance() -> Double
    func deleteTrip(id: UUID)
    func purgeSoftDeletedTrips()
    func updateTitle(for tripId: UUID, title: String)
    func updateNotes(for tripId: UUID, notes: String)
    func saveBadgesJSON(tripId: UUID, badgeIds: [String])
    func addPhoto(to tripId: UUID, image: UIImage, caption: String?) -> TripPhoto?
    func deletePhoto(id: UUID, from tripId: UUID)
    func markSynced(tripId: UUID, conflictVersion: Int)
}

// MARK: - CoreData Implementation

final class CoreDataTripRepository: TripRepository {
    private let persistenceController: PersistenceController

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    private var context: NSManagedObjectContext {
        persistenceController.container.viewContext
    }

    func fetchAllTrips() -> [Trip] {
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = completedTripPredicate
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TripEntity.startDate, ascending: false)]
        request.fetchBatchSize = 25
        guard let entities = try? context.fetch(request) else { return [] }
        return entities.compactMap { tripFromEntity($0, includeTrackPoints: false) }
    }

    func fetchTrips(limit: Int, offset: Int) -> [Trip] {
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = completedTripPredicate
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TripEntity.startDate, ascending: false)]
        request.fetchLimit = limit
        request.fetchOffset = offset
        request.fetchBatchSize = limit
        guard let entities = try? context.fetch(request) else { return [] }
        return entities.compactMap { tripFromEntity($0, includeTrackPoints: false) }
    }

    func fetchTripsWithTrackPoints() -> [Trip] {
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = completedTripPredicate
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TripEntity.startDate, ascending: false)]
        request.fetchBatchSize = 10
        guard let entities = try? context.fetch(request) else { return [] }
        return entities.compactMap { tripFromEntity($0) }
    }

    func fetchTripsModifiedSince(_ date: Date) -> [Trip] {
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "lastModifiedAt > %@ AND syncStatus != %d",
            date as NSDate, SyncStatus.synced.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TripEntity.lastModifiedAt, ascending: true)]
        request.fetchBatchSize = 25
        guard let entities = try? context.fetch(request) else { return [] }
        return entities.compactMap { tripFromEntity($0, includeTrackPoints: false) }
    }

    func fetchTripDetail(id: UUID) -> Trip? {
        guard let entity = fetchEntity(id: id) else { return nil }
        return tripFromEntity(entity)
    }

    func fetchTripCount() -> Int {
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = completedTripPredicate
        return (try? context.count(for: request)) ?? 0
    }

    func fetchLastTripDate() -> Date? {
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = completedTripPredicate
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TripEntity.startDate, ascending: false)]
        request.fetchLimit = 1
        return (try? context.fetch(request).first)?.startDate
    }

    func fetchTripStats() -> (count: Int, totalDistance: Double) {
        let countRequest: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        countRequest.predicate = completedTripPredicate
        let count = (try? context.count(for: countRequest)) ?? 0

        let sumRequest = NSFetchRequest<NSDictionary>(entityName: "TripEntity")
        sumRequest.predicate = completedTripPredicate
        sumRequest.resultType = .dictionaryResultType
        let sumDesc = NSExpressionDescription()
        sumDesc.name = "totalDistance"
        sumDesc.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "distance")])
        sumDesc.expressionResultType = .doubleAttributeType
        sumRequest.propertiesToFetch = [sumDesc]

        let distance: Double
        if let results = try? context.fetch(sumRequest),
           let dict = results.first,
           let total = dict["totalDistance"] as? Double {
            distance = total
        } else {
            distance = 0
        }
        return (count, distance)
    }

    func fetchTotalDistance() -> Double {
        fetchTripStats().totalDistance
    }

    func deleteTrip(id: UUID) {
        guard let entity = fetchEntity(id: id) else { return }
        entity.syncStatus = SyncStatus.pendingDelete.rawValue
        entity.lastModifiedAt = Date()
        persistenceController.save()
    }

    func purgeSoftDeletedTrips() {
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "syncStatus == %d", SyncStatus.pendingDelete.rawValue)
        guard let entities = try? context.fetch(request) else { return }
        for entity in entities {
            if let id = entity.id {
                PhotoStorageService.deletePhotos(for: id)
            }
            context.delete(entity)
        }
        if !entities.isEmpty {
            persistenceController.save()
        }
    }

    func updateTitle(for tripId: UUID, title: String) {
        guard let entity = fetchEntity(id: tripId) else { return }
        entity.title = title.isEmpty ? nil : title
        entity.lastModifiedAt = Date()
        persistenceController.save()
    }

    func updateNotes(for tripId: UUID, notes: String) {
        guard let entity = fetchEntity(id: tripId) else { return }
        entity.tripDescription = notes
        entity.lastModifiedAt = Date()
        persistenceController.save()
    }

    func saveBadgesJSON(tripId: UUID, badgeIds: [String]) {
        guard !badgeIds.isEmpty, let entity = fetchEntity(id: tripId) else { return }
        if let data = try? JSONEncoder().encode(badgeIds),
           let json = String(data: data, encoding: .utf8) {
            entity.badgesJSON = json
            entity.lastModifiedAt = Date()
            persistenceController.save()
        }
    }

    func addPhoto(to tripId: UUID, image: UIImage, caption: String?) -> TripPhoto? {
        guard let filename = PhotoStorageService.savePhoto(image, for: tripId),
              let entity = fetchEntity(id: tripId) else { return nil }

        let photoEntity = TripPhotoEntity(context: context)
        let photoId = UUID()
        photoEntity.id = photoId
        photoEntity.filename = filename
        photoEntity.caption = caption
        photoEntity.timestamp = Date()
        photoEntity.lastModifiedAt = Date()
        photoEntity.sortOrder = Int16(entity.photos?.count ?? 0)
        photoEntity.trip = entity
        entity.lastModifiedAt = Date()
        persistenceController.save()

        return TripPhoto(id: photoId, filename: filename, caption: caption, timestamp: Date())
    }

    func deletePhoto(id: UUID, from tripId: UUID) {
        let request: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let entity = try? context.fetch(request).first {
            PhotoStorageService.deletePhoto(filename: entity.filename ?? "")
            if let trip = entity.trip {
                trip.lastModifiedAt = Date()
            }
            context.delete(entity)
            persistenceController.save()
        }
    }

    func markSynced(tripId: UUID, conflictVersion: Int) {
        guard let entity = fetchEntity(id: tripId) else { return }
        entity.syncStatus = SyncStatus.synced.rawValue
        entity.conflictVersion = Int32(conflictVersion)
        persistenceController.save()
    }

    // MARK: - Private

    private var completedTripPredicate: NSPredicate {
        NSPredicate(format: "endDate != nil AND syncStatus != %d", SyncStatus.pendingDelete.rawValue)
    }

    private func fetchEntity(id: UUID) -> TripEntity? {
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private func tripFromEntity(_ entity: TripEntity, includeTrackPoints: Bool = true) -> Trip? {
        guard let id = entity.id, let startDate = entity.startDate else { return nil }

        let points: [TrackPoint]
        if includeTrackPoints {
            points = (entity.trackPoints?.array as? [TrackPointEntity])?.compactMap { pe in
                guard let pid = pe.id, let ts = pe.timestamp else { return nil }
                return TrackPoint(
                    id: pid, latitude: pe.latitude, longitude: pe.longitude,
                    altitude: pe.altitude, speed: pe.speed, course: pe.course,
                    horizontalAccuracy: pe.horizontalAccuracy, timestamp: ts,
                    isInterpolated: pe.isInterpolated
                )
            } ?? []
        } else {
            points = []
        }

        let photos: [TripPhoto] = (entity.photos?.array as? [TripPhotoEntity])?.compactMap { pe in
            guard let pid = pe.id, let filename = pe.filename, let ts = pe.timestamp else { return nil }
            return TripPhoto(id: pid, filename: filename, caption: pe.caption, timestamp: ts)
        } ?? []

        let badgeIds: [String]
        if let json = entity.badgesJSON,
           let data = json.data(using: .utf8),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            badgeIds = ids
        } else {
            badgeIds = []
        }

        return Trip(
            id: id, startDate: startDate, endDate: entity.endDate,
            distance: entity.distance, maxSpeed: entity.maxSpeed,
            averageSpeed: entity.averageSpeed, trackPoints: points, photos: photos,
            title: entity.title, tripDescription: entity.tripDescription,
            fuelUsed: entity.fuelUsed, elevation: entity.elevation,
            region: entity.region, isPrivate: entity.isPrivate,
            vehicleId: entity.vehicleId, fuelCurrency: entity.fuelCurrency,
            previewPolyline: entity.previewPolyline, earnedBadgeIds: badgeIds
        )
    }
}
