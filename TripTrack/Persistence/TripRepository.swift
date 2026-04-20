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

    // MARK: Sync
    func fetchEntity(id: UUID) -> TripEntity?
    func markSynced(tripId: UUID, conflictVersion: Int, serverCreatedAt: Date)
    func markAllPendingUpload()
    func applyRemoteTrip(_ payload: TripSyncPayload)
    func applyRemoteVehicle(_ payload: VehicleSyncPayload)
    func applyRemotePhoto(_ payload: PhotoSyncPayload)
    func applyRemoteSettings(_ payload: SettingsSyncPayload)
    func deleteTripHard(id: UUID)
    func deleteVehicleHard(id: UUID)
    func deletePhotoHard(id: UUID)
    func markPhotoUploaded(photoId: UUID, remoteURL: String?, thumbnailURL: String, uploadStatus: PhotoUploadStatus)
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
        Task { @MainActor in
            SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: id, action: .delete))
        }
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
            Task { @MainActor in
                SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: tripId, action: .update))
            }
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

        let photo = TripPhoto(id: photoId, filename: filename, caption: caption, timestamp: Date())
        Task { @MainActor in
            SyncEnqueuer.enqueue(SyncOperation(entityType: .photo, entityId: photoId, action: .upload))
            SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: tripId, action: .update))
        }
        return photo
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
            Task { @MainActor in
                SyncEnqueuer.enqueue(SyncOperation(entityType: .photo, entityId: id, action: .delete))
                SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: tripId, action: .update))
            }
        }
    }

    func markSynced(tripId: UUID, conflictVersion: Int) {
        guard let entity = fetchEntity(id: tripId) else { return }
        entity.syncStatus = SyncStatus.synced.rawValue
        entity.conflictVersion = Int32(conflictVersion)
        persistenceController.save()
    }

    func markSynced(tripId: UUID, conflictVersion: Int, serverCreatedAt: Date) {
        guard let entity = fetchEntity(id: tripId) else { return }
        entity.syncStatus = SyncStatus.synced.rawValue
        entity.conflictVersion = Int32(conflictVersion)
        entity.serverCreatedAt = serverCreatedAt
        saveIfNeeded()
    }

    // MARK: - Private

    private var completedTripPredicate: NSPredicate {
        NSPredicate(format: "endDate != nil AND syncStatus != %d", SyncStatus.pendingDelete.rawValue)
    }

    func fetchEntity(id: UUID) -> TripEntity? {
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

    // MARK: - Sync Helpers

    func markAllPendingUpload() {
        let trips = NSBatchUpdateRequest(entityName: "TripEntity")
        trips.propertiesToUpdate = ["syncStatus": SyncStatus.pendingUpload.rawValue]
        _ = try? context.execute(trips)

        let vehicles = NSBatchUpdateRequest(entityName: "VehicleEntity")
        vehicles.propertiesToUpdate = ["syncStatus": SyncStatus.pendingUpload.rawValue]
        _ = try? context.execute(vehicles)

        let photos = NSBatchUpdateRequest(entityName: "TripPhotoEntity")
        photos.propertiesToUpdate = ["syncStatus": SyncStatus.pendingUpload.rawValue]
        _ = try? context.execute(photos)

        let settings = NSBatchUpdateRequest(entityName: "UserSettingsEntity")
        settings.propertiesToUpdate = ["syncStatus": SyncStatus.pendingUpload.rawValue]
        _ = try? context.execute(settings)

        context.refreshAllObjects()
    }

    func applyRemoteTrip(_ p: TripSyncPayload) {
        let entity = fetchEntity(id: p.id) ?? TripEntity(context: context)
        if entity.id != nil,
           entity.syncStatus == SyncStatus.pendingUpload.rawValue,
           Int(entity.conflictVersion) >= p.conflictVersion {
            return
        }
        entity.id = p.id
        entity.title = p.title
        entity.tripDescription = p.description
        entity.startDate = p.startDate
        entity.endDate = p.endDate
        entity.distance = p.distance
        entity.maxSpeed = p.maxSpeed
        entity.averageSpeed = p.averageSpeed
        entity.fuelUsed = p.fuelUsed
        entity.elevation = p.elevation
        entity.region = p.region
        entity.isPrivate = p.isPrivate
        entity.vehicleId = p.vehicleId
        entity.fuelCurrency = p.fuelCurrency
        entity.previewPolyline = p.previewPolyline.flatMap { Data(base64Encoded: $0) }
        entity.badgesJSON = p.badgesJson
        entity.xpEarned = Int32(p.xpEarned ?? 0)
        entity.conflictVersion = Int32(p.conflictVersion)
        entity.lastModifiedAt = p.lastModifiedAt
        entity.syncStatus = SyncStatus.synced.rawValue

        if let existingTPs = entity.trackPoints as? Set<TrackPointEntity> {
            for tp in existingTPs { context.delete(tp) }
        }
        for pt in p.trackPoints {
            let tpe = TrackPointEntity(context: context)
            tpe.id = pt.id
            tpe.latitude = pt.latitude
            tpe.longitude = pt.longitude
            tpe.altitude = pt.altitude
            tpe.speed = pt.speed
            tpe.course = pt.course
            tpe.horizontalAccuracy = pt.horizontalAccuracy
            tpe.timestamp = pt.timestamp
            tpe.isInterpolated = pt.isInterpolated
            tpe.trip = entity
        }

        if let localPhotos = entity.photos?.array as? [TripPhotoEntity] {
            let serverIds = Set((p.photos ?? []).map { $0.id })
            for pe in localPhotos {
                guard let pid = pe.id else { continue }
                if pe.uploadStatus == PhotoUploadStatus.localOnly.rawValue {
                    continue
                }
                if !serverIds.contains(pid) {
                    context.delete(pe)
                }
            }
        }

        saveIfNeeded()
    }

    func applyRemoteVehicle(_ p: VehicleSyncPayload) {
        let req: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", p.id as CVarArg)
        req.fetchLimit = 1
        let entity = (try? context.fetch(req).first) ?? VehicleEntity(context: context)
        entity.id = p.id
        entity.name = p.name
        entity.avatarEmoji = p.avatarEmoji
        entity.odometerKm = p.odometerKm
        entity.vehicleLevel = Int32(p.level)
        entity.stickersJSON = p.stickersJson
        entity.cityConsumption = p.cityConsumption
        entity.highwayConsumption = p.highwayConsumption
        entity.fuelPrice = p.fuelPrice
        entity.conflictVersion = Int32(p.conflictVersion)
        entity.lastModifiedAt = p.lastModifiedAt
        entity.syncStatus = SyncStatus.synced.rawValue
        saveIfNeeded()
    }

    func applyRemotePhoto(_ p: PhotoSyncPayload) {
        let req: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", p.id as CVarArg)
        req.fetchLimit = 1
        let entity = (try? context.fetch(req).first) ?? TripPhotoEntity(context: context)
        entity.id = p.id
        if let trip = fetchEntity(id: p.tripId) {
            entity.trip = trip
        }
        entity.filename = p.filename
        entity.caption = p.caption
        entity.timestamp = p.timestamp
        entity.remoteURL = p.remoteUrl
        entity.thumbnailURL = p.thumbnailUrl
        entity.sortOrder = Int16(p.sortOrder)
        entity.uploadStatus = p.uploadStatus
        entity.lastModifiedAt = p.lastModifiedAt
        entity.syncStatus = SyncStatus.synced.rawValue
        saveIfNeeded()
    }

    func applyRemoteSettings(_ p: SettingsSyncPayload) {
        let req: NSFetchRequest<UserSettingsEntity> = UserSettingsEntity.fetchRequest()
        req.fetchLimit = 1
        let entity = (try? context.fetch(req).first) ?? UserSettingsEntity(context: context)
        entity.id = p.id
        entity.avatarEmoji = p.avatarEmoji
        entity.themeMode = p.themeMode
        entity.language = p.language
        entity.distanceUnit = p.distanceUnit
        entity.volumeUnit = p.volumeUnit
        entity.fuelConsumption = p.fuelConsumption
        entity.fuelPrice = p.fuelPrice
        entity.fuelCurrency = p.fuelCurrency
        entity.selectedVehicleId = p.selectedVehicleId
        entity.profileLevel = Int32(p.profileLevel)
        entity.profileXP = Int64(p.profileXp)
        entity.currentStreak = Int32(p.currentStreak)
        entity.bestStreak = Int32(p.bestStreak)
        entity.lastTripDate = p.lastTripDate
        entity.conflictVersion = Int32(p.conflictVersion)
        entity.lastModifiedAt = p.lastModifiedAt
        entity.syncStatus = SyncStatus.synced.rawValue
        saveIfNeeded()
    }

    func deleteTripHard(id: UUID) {
        if let e = fetchEntity(id: id) {
            context.delete(e)
            saveIfNeeded()
        }
    }

    func deleteVehicleHard(id: UUID) {
        let req: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let e = try? context.fetch(req).first {
            context.delete(e)
            saveIfNeeded()
        }
    }

    func deletePhotoHard(id: UUID) {
        let req: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let e = try? context.fetch(req).first {
            context.delete(e)
            saveIfNeeded()
        }
    }

    func markPhotoUploaded(photoId: UUID, remoteURL: String?, thumbnailURL: String, uploadStatus: PhotoUploadStatus) {
        let req: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", photoId as CVarArg)
        if let e = try? context.fetch(req).first {
            e.thumbnailURL = thumbnailURL
            if let r = remoteURL { e.remoteURL = r }
            e.uploadStatus = uploadStatus.rawValue
            e.lastModifiedAt = Date()
            saveIfNeeded()
        }
    }

    private func saveIfNeeded() {
        if context.hasChanges {
            try? context.save()
        }
    }
}
