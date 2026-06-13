import Foundation
import CoreData
import CoreLocation
import UIKit
import OSLog

// MARK: - Protocol

protocol TripRepository {
    func fetchTrips(limit: Int, offset: Int) -> [Trip]
    func fetchAllTrips() -> [Trip]
    func hasAnyPrivateTrip() -> Bool
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
    func updatePrivacy(for tripId: UUID, isPrivate: Bool)
    func updateVehicle(for tripId: UUID, vehicleId: UUID?)
    /// Resets server-side metadata after a successful `/trips/delete` triggered
    /// by un-publishing. The local entity stays — only the bookkeeping that
    /// links it to the server copy is cleared, so subsequent re-publish treats
    /// it as a fresh upload (`.upload`, not `.update`).
    func markUnpublished(tripId: UUID)
    @discardableResult
    func migrateAllTripsToPrivate() -> [UUID]
    func saveBadgesJSON(tripId: UUID, badgeIds: [String])
    func addPhoto(to tripId: UUID, image: UIImage, caption: String?) -> TripPhoto?
    func deletePhoto(id: UUID, from tripId: UUID)
    func markSynced(tripId: UUID, conflictVersion: Int)

    // MARK: Sync
    func fetchEntity(id: UUID) -> TripEntity?
    /// Builds a `TripSyncPayload` (track-point decode + movement-split + photo
    /// metadata) on a BACKGROUND context, off the main actor. `uploadTrip` used
    /// to do this on the main viewContext, decoding every track point of every
    /// trip during a sync drain — the residual lag on long (thousands-of-points)
    /// trips that round 3's off-main encode/gzip didn't cover.
    func fetchTripSyncPayloadAsync(id: UUID) async -> TripSyncPayload?
    func markSynced(tripId: UUID, conflictVersion: Int, serverCreatedAt: Date)
    func markAllPendingUpload()
    func applyRemoteTrip(_ payload: TripSyncPayload)
    func applyRemoteVehicle(_ payload: VehicleSyncPayload)
    func applyRemotePhoto(_ payload: PhotoSyncPayload)
    /// Flushes pending CoreData changes after a batch of `applyRemote*`
    /// calls. The applyRemote methods skip per-item saves so a `/sync/pull`
    /// with 50 trips makes ONE save instead of 50.
    func flushPendingApplies()
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

    /// Async variant of `fetchAllTrips`. Runs the entire fetch on a private
    /// queue background context so the main thread stays free for the
    /// SwiftUI refresh control animation. Used by `FeedViewModel.loadTripsAsync`
    /// which is invoked from pull-to-refresh — on older hardware (iPhone 12
    /// with 70+ trips) the synchronous viewContext fetch caused a visible
    /// 100-300ms freeze of the refresh spinner.
    ///
    /// Trip is a value type, so the returned array is safe to consume on
    /// any actor. NSManagedObject access stays inside the perform block
    /// (the context's private queue) — no entity leaks across queues.
    func fetchAllTripsAsync() async -> [Trip] {
        let bgContext = persistenceController.container.newBackgroundContext()
        return await withCheckedContinuation { (cont: CheckedContinuation<[Trip], Never>) in
            bgContext.perform {
                let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
                request.predicate = self.completedTripPredicate
                request.sortDescriptors = [NSSortDescriptor(keyPath: \TripEntity.startDate, ascending: false)]
                request.fetchBatchSize = 25
                guard let entities = try? bgContext.fetch(request) else {
                    cont.resume(returning: [])
                    return
                }
                let trips = entities.compactMap { self.tripFromEntity($0, includeTrackPoints: false) }
                cont.resume(returning: trips)
            }
        }
    }

    func fetchTripSyncPayloadAsync(id: UUID) async -> TripSyncPayload? {
        let bgContext = persistenceController.container.newBackgroundContext()
        return await withCheckedContinuation { (cont: CheckedContinuation<TripSyncPayload?, Never>) in
            bgContext.perform {
                let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                request.fetchLimit = 1
                guard let entity = try? bgContext.fetch(request).first else {
                    cont.resume(returning: nil)
                    return
                }
                // tripFromEntity (incl. track points) + TripSyncPayload.init
                // (movement-split + photo meta) run on the bg queue; the result
                // is a value-type payload — no managed object crosses the hop.
                guard let trip = self.tripFromEntity(entity) else {
                    cont.resume(returning: nil)
                    return
                }
                let payload = TripSyncPayload(trip: trip, entity: entity)
                cont.resume(returning: payload)
            }
        }
    }

    /// Cheap existence probe — `fetchLimit = 1` + predicate combo bails as
    /// soon as Core Data finds one match, no entity decode. Used by feed
    /// empty-state to decide whether to surface the "publish your first
    /// trip" CTA without paying for `fetchAllTrips()` on every render.
    func hasAnyPrivateTrip() -> Bool {
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            completedTripPredicate,
            NSPredicate(format: "isPrivate == YES"),
        ])
        request.fetchLimit = 1
        return ((try? context.count(for: request)) ?? 0) > 0
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
        // If the trip never reached the server (no serverCreatedAt) we can
        // skip the soft-delete + enqueue dance entirely — there's nothing for
        // the server to delete. Without this short-circuit, a private trip
        // deleted while Cloud Sync is OFF would sit in `pendingDelete` state
        // forever: the SyncEnqueuer privacy gate blocks the .delete op (no
        // server copy → nothing publish-related to clean up), and
        // deleteTripHard only runs from the transport on a successful
        // server-delete. Result: ghost entry hidden in the UI but never
        // garbage-collected.
        if entity.serverCreatedAt == nil {
            deleteTripHard(id: id)
            return
        }
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
        // Only flip syncStatus when the change can actually drain. For a
        // private trip at Cloud Sync OFF the per-op gate denies enqueue, so
        // marking pendingUpload would leave the entity stuck in that state
        // forever — visible as phantom "1 pending" in the status sheet.
        // Cloud Sync ON or public trip → both can sync, so flip as before.
        if Self.shouldFlipPendingUpload(for: entity) {
            entity.syncStatus = SyncStatus.pendingUpload.rawValue
        }
        persistenceController.save()
    }

    func updateNotes(for tripId: UUID, notes: String) {
        guard let entity = fetchEntity(id: tripId) else { return }
        entity.tripDescription = notes
        entity.lastModifiedAt = Date()
        if Self.shouldFlipPendingUpload(for: entity) {
            entity.syncStatus = SyncStatus.pendingUpload.rawValue
        }
        persistenceController.save()
    }

    /// Reassign (or clear, when nil) the vehicle on a saved trip. Metadata-only
    /// like updateTitle/updateNotes — it does NOT rebalance vehicle odometers or
    /// stats (those accumulate at record time). `vehicleId` already rides the
    /// existing sync payload, so no transport change is needed.
    func updateVehicle(for tripId: UUID, vehicleId: UUID?) {
        guard let entity = fetchEntity(id: tripId) else { return }
        entity.vehicleId = vehicleId
        entity.lastModifiedAt = Date()
        if Self.shouldFlipPendingUpload(for: entity) {
            entity.syncStatus = SyncStatus.pendingUpload.rawValue
        }
        persistenceController.save()
    }

    /// True when a metadata edit on `entity` should mark it pending for the
    /// sync queue. Returns false for private trips at Cloud Sync OFF — those
    /// can't drain (the privacy gate denies them), so flipping their status
    /// leaves a phantom pending op forever. When the user later enables
    /// Cloud Sync, `markAllPendingUpload` flips everything back to pending.
    /// Nonisolated: callers run on whatever context the repo update lives in
    /// (viewContext = main thread for now, but we don't want to force that).
    /// Reads only — `cloudSyncEnabled` is a UserDefaults-backed Bool that's
    /// safe to read from any thread; `entity.isPrivate` access matches the
    /// caller's current isolation.
    private static func shouldFlipPendingUpload(for entity: TripEntity) -> Bool {
        if SettingsManager.shared.cloudSyncEnabled { return true }
        return entity.isPrivate == false
    }

    func updatePrivacy(for tripId: UUID, isPrivate: Bool) {
        guard let entity = fetchEntity(id: tripId) else { return }
        let wasSynced = entity.serverCreatedAt != nil
        let cloudOn = SettingsManager.shared.cloudSyncEnabled

        // Privacy-first split:
        //   * Going public → upload (or update if already on server). Photos
        //     of a freshly-public trip get enqueued so the social card has
        //     visuals immediately, not after the next /trips/upsert.
        //   * Going private + already on server + Cloud Sync OFF → unpublish
        //     (server-delete, local stays). The user wants ZERO trace.
        //   * Going private + Cloud Sync ON → just an update (server keeps
        //     the trip, just hides it from feed via is_private flag).
        //   * Going private + never on server → no-op beyond the local flip.
        let pendingOp: SyncOperation.Action?
        let syncStatus: SyncStatus
        let enqueuePhotos: Bool
        if !isPrivate {
            pendingOp = wasSynced ? .update : .upload
            syncStatus = .pendingUpload
            enqueuePhotos = true
        } else if wasSynced && !cloudOn {
            // .pendingUpload (rather than .synced) so a concurrent /sync/pull
            // can't overwrite our `isPrivate=true` flip via the skip-guard
            // in `applyRemoteTrip` (which only honors locally-pending state).
            // The .unpublish op is what carries the server-delete; once it
            // lands, `markUnpublished` resets status back to .synced.
            pendingOp = .unpublish
            syncStatus = .pendingUpload
            enqueuePhotos = false
        } else if wasSynced {
            pendingOp = .update
            syncStatus = .pendingUpload
            enqueuePhotos = false
        } else {
            pendingOp = nil
            syncStatus = .synced
            enqueuePhotos = false
        }

        entity.isPrivate = isPrivate
        entity.lastModifiedAt = Date()
        entity.syncStatus = syncStatus.rawValue
        persistenceController.save()

        if let action = pendingOp {
            Task { @MainActor in
                // Cancel any conflicting queued ops BEFORE enqueueing the
                // new one. Both directions need this:
                //   * Going .unpublish: drop any queued .upload/.update for
                //     the trip + photo ops so they don't briefly publish
                //     before our server-delete lands.
                //   * Going .upload/.update (re-publish after a previous
                //     unpublish): drop the queued .unpublish so it doesn't
                //     server-delete a trip we just decided to keep public.
                SyncQueue.shared.cancelOperations(for: tripId, entityType: .trip)
                if action == .unpublish {
                    let photoIds = self.photoIdsForTrip(tripId: tripId)
                    for pid in photoIds {
                        SyncQueue.shared.cancelOperations(for: pid, entityType: .photo)
                    }
                }
                SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: tripId, action: action))
                if enqueuePhotos {
                    self.enqueuePhotosForPublicTrip(tripId: tripId)
                }
            }
        }
    }

    @MainActor
    private func photoIdsForTrip(tripId: UUID) -> [UUID] {
        let req: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
        req.predicate = NSPredicate(format: "trip.id == %@", tripId as CVarArg)
        return (try? context.fetch(req))?.compactMap(\.id) ?? []
    }

    func markUnpublished(tripId: UUID) {
        guard let entity = fetchEntity(id: tripId) else { return }
        // Do NOT force isPrivate = true — the user may have flipped the trip
        // back to public while the .unpublish op was in flight. In that
        // case the queue already holds a fresh `.upload` op (since we
        // entered the public branch with `wasSynced = true && cloudOn`
        // false → `pendingOp = .upload`). Clobbering isPrivate here would
        // wipe the user's most recent intent. We just clear the
        // server-side bookkeeping so a re-publish enqueues `.upload`,
        // not `.update`.
        entity.serverCreatedAt = nil
        entity.conflictVersion = 0
        if entity.isPrivate {
            entity.syncStatus = SyncStatus.synced.rawValue
        }
        entity.lastModifiedAt = Date()
        persistenceController.save()
    }

    /// Forces fresh photo-upload ops for every photo of a trip that was just
    /// flipped public. Without this, photos taken while the trip was private
    /// would have been blocked by the per-op gate (parent was private at
    /// enqueue time) and stay local-only forever — the public feed card would
    /// render the trip without any of its photos.
    /// Filter is by `remoteURL == nil` — covers both never-uploaded photos
    /// (thumb missing) and thumb-only-uploaded photos (which transport now
    /// marks as `.uploaded` so the queue won't auto-retry them, but the
    /// original blob still needs to land before fullscreen view works).
    @MainActor
    private func enqueuePhotosForPublicTrip(tripId: UUID) {
        let req: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
        req.predicate = NSPredicate(
            format: "trip.id == %@ AND remoteURL == nil",
            tripId as CVarArg
        )
        guard let photos = try? context.fetch(req) else { return }
        for photo in photos {
            guard let pid = photo.id else { continue }
            SyncEnqueuer.enqueue(SyncOperation(entityType: .photo, entityId: pid, action: .upload))
        }
    }

    /// One-time migration for the privacy-by-default launch. Flips every
    /// pre-existing public trip to `isPrivate = true`. For trips that have a
    /// `serverCreatedAt` (already on the server from a prior Cloud Sync ON
    /// era), returns those IDs so the caller can enqueue `.unpublish` ops to
    /// strip the server copies — otherwise the user would silently keep
    /// trips public on the server even after the local default flipped.
    /// Runs once per install (guarded by UserDefaults at the call site).
    /// Note: we do NOT flip `syncStatus` to `pendingUpload` here. With the
    /// privacy-first SyncEnqueuer gate, a private trip at Cloud Sync OFF
    /// would never drain — leaving the queue with phantom pending work.
    @discardableResult
    func migrateAllTripsToPrivate() -> [UUID] {
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "isPrivate == NO")
        guard let entities = try? context.fetch(request) else { return [] }
        let now = Date()
        var serverSideToUnpublish: [UUID] = []
        for entity in entities {
            entity.isPrivate = true
            entity.lastModifiedAt = now
            if entity.serverCreatedAt != nil, let id = entity.id {
                serverSideToUnpublish.append(id)
            }
        }
        persistenceController.save()
        return serverSideToUnpublish
    }

    func saveBadgesJSON(tripId: UUID, badgeIds: [String]) {
        guard !badgeIds.isEmpty, let entity = fetchEntity(id: tripId) else { return }
        if let data = try? JSONEncoder().encode(badgeIds),
           let json = String(data: data, encoding: .utf8) {
            entity.badgesJSON = json
            entity.lastModifiedAt = Date()
            if Self.shouldFlipPendingUpload(for: entity) {
                entity.syncStatus = SyncStatus.pendingUpload.rawValue
            }
            persistenceController.save()
            // Enqueue is unconditional — the gate filters per-op, so harmless
            // for private trips at OFF (denied silently).
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
            // Feed cards include a "has photos" indicator + preview thumbnail
            // — without this notification the card stays stale until the next
            // pull-to-refresh because Feed only reloads on recording-end and
            // sync-pull events. `delta:+1` lets SocialFeedStore bump
            // `photoCount` optimistically before the upload completes.
            NotificationCenter.default.post(
                name: .tripPhotosChanged, object: nil,
                userInfo: ["tripId": tripId, "delta": 1])
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
                NotificationCenter.default.post(
                    name: .tripPhotosChanged, object: nil,
                    userInfo: ["tripId": tripId, "delta": -1])
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
        // Scope each batch update to the CURRENT user's localUserId so we
        // never re-upload another account's leftover entities. Without
        // this, signing out User A and signing in User B on the same
        // device caused User A's trips/vehicles/photos to be flipped to
        // pendingUpload, then enqueued during User B's `performFirstSync`
        // — server rejected with TripNotFound (good), but the client UI
        // showed User A's trips because no layer filters by userId.
        let userId = SettingsManager.shared.localUserId as NSUUID
        let predicate = NSPredicate(format: "userId == %@", userId)

        let trips = NSBatchUpdateRequest(entityName: "TripEntity")
        trips.predicate = predicate
        trips.propertiesToUpdate = ["syncStatus": SyncStatus.pendingUpload.rawValue]
        _ = try? context.execute(trips)

        let vehicles = NSBatchUpdateRequest(entityName: "VehicleEntity")
        vehicles.predicate = predicate
        vehicles.propertiesToUpdate = ["syncStatus": SyncStatus.pendingUpload.rawValue]
        _ = try? context.execute(vehicles)

        // TripPhotoEntity has no `userId` column (only a `trip` relationship),
        // and NSBatchUpdateRequest can't traverse relationships — CoreData's
        // batch SQL generator refuses to emit a JOIN, throwing an NSException
        // that `try?` cannot catch. So we fall back to fetch + iterate. Photo
        // count per user is in the hundreds at worst; the perf hit is invisible.
        let photoFetch: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
        photoFetch.predicate = NSPredicate(format: "trip.userId == %@", userId)
        if let userPhotos = try? context.fetch(photoFetch) {
            for photo in userPhotos { photo.syncStatus = SyncStatus.pendingUpload.rawValue }
        }

        let settings = NSBatchUpdateRequest(entityName: "UserSettingsEntity")
        settings.predicate = NSPredicate(format: "id == %@", userId)
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

        // Only replace track points when server actually sent them (detail/push).
        // Pull delta omits track points — keep local ones intact.
        if let serverPoints = p.trackPoints {
            if let existingTPs = entity.trackPoints as? Set<TrackPointEntity> {
                for tp in existingTPs { context.delete(tp) }
            }
            for pt in serverPoints {
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

        // Save deferred to PullApplier.flushPendingApplies() — batches a
        // /sync/pull's worth of writes into a single CoreData save call.
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
        // Save deferred — see flushPendingApplies().
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
        // Save deferred — see flushPendingApplies().
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
        // Save deferred — see flushPendingApplies().
    }

    /// Persist all `applyRemote*` mutations accumulated since the last
    /// flush. PullApplier calls this once per pull instead of after every
    /// row, collapsing N saves into 1.
    func flushPendingApplies() {
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
            // Surface CoreData save failures via OSLog instead of `try?` —
            // a silent save failure during sync apply is the kind of bug
            // that takes weeks to spot via "user trip didn't appear".
            do {
                try context.save()
            } catch {
                let logger = Logger(subsystem: "com.triptrack", category: "core-data")
                logger.error("saveIfNeeded failed: \(error.localizedDescription)")
            }
        }
    }
}
