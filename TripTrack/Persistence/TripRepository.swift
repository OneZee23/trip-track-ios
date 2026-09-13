import Foundation
import CoreData
import CoreLocation
import UIKit
import OSLog

// MARK: - Protocol

/// Поездка для предфильтра мест: без точек, снимков и отметок.
struct TripPreviewRef: Identifiable, Equatable {
    let id: UUID
    let startDate: Date
    let previewPolyline: Data?
    var previewCoordinates: [CLLocationCoordinate2D] {
        previewPolyline.map(Trip.decodePolyline) ?? []
    }
}

protocol TripRepository {
    func fetchTrips(limit: Int, offset: Int) -> [Trip]
    func fetchAllTrips() -> [Trip]
    /// Свои поездки, стартовавшие внутри окна дат. См. реализацию: окно режет
    /// база, а не фильтр в памяти.
    func fetchTrips(from start: Date, to end: Date) -> [Trip]
    func hasAnyPrivateTrip() -> Bool
    /// Every completed trip, carrying the simplified preview polyline but NOT
    /// its track points. See the implementation for why that matters.
    func fetchTripsForMap() -> [Trip]
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
    /// Пометить поездку трансфером (человек ехал пассажиром) или снять метку.
    func updateTransfer(for tripId: UUID, isTransfer: Bool)
    /// Photos whose only copy is the server's — see the implementation.
    func serverOnlyPhotoIds(tripId: UUID) -> [UUID]
    func adoptRescuedPhoto(id: UUID, filename: String)
    func updateVehicle(for tripId: UUID, vehicleId: UUID?)
    func updateCompanions(for tripId: UUID, companions: [TripCompanion])
    /// Wipes the on-device companions cache (`companionsJSON`) for EVERY
    /// local trip. Companions are per-account data — see `AuthService
    /// .clearLocalIdentity` — but local trips themselves are device-scoped
    /// (`TripEntity.userId` is `SettingsManager.localUserId`, a stable
    /// per-device id that does NOT change across a sign-out/sign-in), so
    /// they survive an account switch on their own. Without this, the next
    /// account signing in on the same device would see whichever roster the
    /// PREVIOUS account last cached on that trip.
    func clearCompanionsCache()
    /// Resets server-side metadata after a successful `/trips/delete` triggered
    /// by un-publishing. The local entity stays — only the bookkeeping that
    /// links it to the server copy is cleared, so subsequent re-publish treats
    /// it as a fresh upload (`.upload`, not `.update`).
    func markUnpublished(tripId: UUID)
    @discardableResult
    func migrateAllTripsToPrivate() -> [UUID]
    func saveBadgesJSON(tripId: UUID, badgeIds: [String])
    func addPhoto(to tripId: UUID, image: UIImage, caption: String?, capturedAt: Date?, latitude: Double?, longitude: Double?) -> TripPhoto?
    func deletePhoto(id: UUID, from tripId: UUID)

    // MARK: Отметки на маршруте
    func addCheckpoint(_ checkpoint: TripCheckpoint, to tripId: UUID) -> TripCheckpoint?
    /// Возвращают id поездки — чтобы вызывающий мог поставить её в очередь синка.
    @discardableResult func updateCheckpoint(id: UUID, name: String?, photoId: UUID?, photoIds: [UUID]) -> UUID?
    @discardableResult func deleteCheckpoint(id: UUID) -> UUID?
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
    /// Tombstone-safe delete — see the implementation for why an unmirrored
    /// trip must survive a server tombstone.
    @discardableResult
    func deleteTripHardIfMirrored(id: UUID) -> Bool
    func tripId(forPhoto id: UUID) -> UUID?
    /// Library size, not sync progress. See the implementation.
    func countLiveTrips() -> Int
    /// Derives the odometer from the trips assigned to each vehicle. See the
    /// implementation for why it is derived rather than accumulated.
    func recomputeOdometers(forVehicles vehicleIds: [UUID])
    /// Whole-garage version, for when the library changes wholesale.
    func recomputeAllVehicleOdometers()
    func deleteVehicleHard(id: UUID)
    /// «Отправлено и подтверждено» для машины. См. реализацию.
    func markVehicleSynced(id: UUID, conflictVersion: Int)
    func deletePhotoHard(id: UUID)
    func markPhotoUploaded(photoId: UUID, remoteURL: String?, thumbnailURL: String, uploadStatus: PhotoUploadStatus)

    // MARK: Journeys (0.6.6)
    func fetchJourneys() -> [Journey]
    func fetchJourney(id: UUID) -> Journey?
    /// Upsert. Взводит `pendingUpload` по тому же правилу, что и у поездок.
    @discardableResult func saveJourney(_ journey: Journey) -> Journey
    func markJourneyDeleted(id: UUID)
    func deleteJourneyHard(id: UUID)
    func journeyContaining(tripId: UUID) -> Journey?
    func journeyOverlapping(start: Date, end: Date?, excluding: UUID?) -> Journey?
    func trips(in journey: Journey) -> [Trip]
    func journeySyncStatus(id: UUID) -> Int16?
    func applyRemoteJourney(_ payload: JourneySyncPayload)
    func markJourneySynced(id: UUID, conflictVersion: Int)

    // MARK: Места (0.6.8)
    /// Выведенное значение: `pendingUpload` НЕ взводится, уедет с первой
    /// настоящей правкой поездки.
    func setPlaceId(forCheckpoint id: UUID, placeId: UUID)
    /// Отметки завершённых поездок, у которых места ещё нет.
    func checkpointsWithoutPlace() -> [(checkpoint: TripCheckpoint, tripId: UUID)]
    /// Координаты отметок места — для центроида.
    func checkpointCoordinates(placeId: UUID) -> [CLLocationCoordinate2D]
    /// Лёгкая выборка для предфильтра: id, старт и превью, без снимков,
    /// отметок и точек. `needingPlaceMatch: true` — только ещё не сверенные.
    func tripPreviews(needingPlaceMatch: Bool) -> [TripPreviewRef]
    func markPlacesMatched(tripId: UUID)
    /// Пачкой: сверка библиотеки помечает сотни поездок одним сохранением.
    func markPlacesMatched(tripIds: [UUID])
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

    /// Свои поездки, стартовавшие в окне — включительно с обоих концов, по
    /// времени старта.
    ///
    /// Окно отрезает БАЗА, а не фильтр в памяти. `fetchAllTrips()` поднимает
    /// всю библиотеку и у КАЖДОЙ поездки материализует связи — снимки, отметки
    /// и разбор `photoIdsJSON` (см. `tripFromEntity`): тысяча записей за пять
    /// лет ради шести внутри недели. Лист объединения зовёт это с главного
    /// потока при каждом открытии, и замирал тем сильнее, чем дольше человек
    /// ездит, — то есть у самых своих людей хуже всего. Предикат тот же, что у
    /// `trips(in:)`: одно правило «поездка в окне», два вызывающих.
    func fetchTrips(from start: Date, to end: Date) -> [Trip] {
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            completedTripPredicate,
            NSPredicate(format: "startDate >= %@", start as NSDate),
            NSPredicate(format: "startDate <= %@", end as NSDate),
        ])
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TripEntity.startDate, ascending: true)]
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

    /// Trips for «Моя карта».
    ///
    /// Track points are deliberately left behind. This runs on the view
    /// context — the main actor — and materialising every point of every trip
    /// meant thousands of managed objects per trip before the map could draw
    /// anything: on a large library that is a multi-second freeze on opening
    /// the tab, for data the map never looks at. It draws the simplified
    /// preview polyline, and the one route that needs per-point speed colours
    /// is fetched on its own when you select it.
    ///
    /// The exception is a trip saved before previews existed: with no polyline
    /// there is nothing else to draw it from, so those — and only those — still
    /// pay for their points.
    func fetchTripsForMap() -> [Trip] {
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = completedTripPredicate
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TripEntity.startDate, ascending: false)]
        request.fetchBatchSize = 40
        guard let entities = try? context.fetch(request) else { return [] }
        return entities.compactMap {
            tripFromEntity($0, includeTrackPoints: $0.previewPolyline == nil)
        }
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
        // Проезды через места — без связи с поездкой (как `JourneyEntity`),
        // каскад их не заберёт: история места не должна помнить поездку,
        // которой у человека больше нет — ни после мягкого удаления, ни после
        // твёрдого.
        CoreDataPlaceStore(context: context).deletePasses(tripId: id)
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
        let vehicleId = entity.vehicleId
        entity.syncStatus = SyncStatus.pendingDelete.rawValue
        entity.lastModifiedAt = Date()
        // A trip the user deleted stops counting towards the car's mileage at
        // the same moment it disappears from the feed, not at some later sync.
        if let vehicleId { recomputeOdometers(forVehicles: [vehicleId]) }
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
        // Everything that reaches this method came out of the editor, so a
        // non-empty title here is a person's choice — even when they typed the
        // same date the app would have stamped. Clearing the field puts the
        // trip back to unnamed.
        entity.titleIsCustom = !title.isEmpty
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
    /// Трансфер: человек ехал пассажиром — такси, автобус, чужая машина.
    ///
    /// Снимает машину с поездки: держать её было бы враньём — она никуда не
    /// ехала. Пробег машины пересчитывается там же, где и при обычной смене
    /// машины, поэтому километры трансфера уходят с её одометра.
    func updateTransfer(for tripId: UUID, isTransfer: Bool) {
        guard let entity = fetchEntity(id: tripId) else { return }
        let previousVehicleId = entity.vehicleId
        entity.isTransfer = isTransfer
        if isTransfer { entity.vehicleId = nil }
        entity.lastModifiedAt = Date()
        if Self.shouldFlipPendingUpload(for: entity) {
            entity.syncStatus = SyncStatus.pendingUpload.rawValue
        }
        recomputeOdometers(forVehicles: [previousVehicleId].compactMap { $0 })
        persistenceController.save()
    }

    func updateVehicle(for tripId: UUID, vehicleId: UUID?) {
        guard let entity = fetchEntity(id: tripId) else { return }
        // Both cars have to be recomputed, not just the new one: the odometer
        // is derived from the trips pointing at it, so moving a trip has to
        // take its kilometres OFF the old car as well as put them on the new.
        // Capture the previous owner before overwriting it.
        let previousVehicleId = entity.vehicleId
        entity.vehicleId = vehicleId
        entity.lastModifiedAt = Date()
        if Self.shouldFlipPendingUpload(for: entity) {
            entity.syncStatus = SyncStatus.pendingUpload.rawValue
        }
        recomputeOdometers(forVehicles: [previousVehicleId, vehicleId].compactMap { $0 })
        persistenceController.save()
    }

    /// Replace the trip's cached companion roster.
    ///
    /// The ONLY caller in production is `CompanionsStore.list(tripId:)`,
    /// after a successful `/companions/list` response — this is a cache
    /// write, not user-entered data. `companions: []` clears the column
    /// rather than leaving a stale roster around (e.g. the last companion
    /// having been removed).
    ///
    /// The `guard let entity` below is not just a null-check: it is the
    /// WHOLE mechanism that keeps a foreign trip from ever gaining a local
    /// row. `CompanionsStore.list` calls this unconditionally after any
    /// successful fetch, own trip or not — a trip this device doesn't have
    /// locally (someone else's) simply has no entity to find, so the call
    /// is a no-op. See `CompanionsCachePersistenceTests` for the row-count
    /// proof.
    ///
    /// Purely local: the sync payload has no field for companions, so this
    /// deliberately does NOT flip the trip to pending-upload. Marking it would
    /// queue an upload that carries none of the change — cost with no effect,
    /// and on a metered connection that is somebody's data.
    func updateCompanions(for tripId: UUID, companions: [TripCompanion]) {
        guard let entity = fetchEntity(id: tripId) else { return }
        if companions.isEmpty {
            entity.companionsJSON = nil
        } else if let data = try? JSONEncoder().encode(companions),
                  let json = String(data: data, encoding: .utf8) {
            entity.companionsJSON = json
        } else {
            return
        }
        // Deliberately does NOT touch `lastModifiedAt` — that field is the
        // last-write-wins clock the sync layer compares against the
        // server's copy (`fetchTripsModifiedSince`, `applyRemoteTrip`'s
        // conflict check). This is a pure cache write triggered by simply
        // OPENING the trip detail screen, not a change to the trip's own
        // data — bumping the clock here made every detail-screen visit look
        // like a newer edit than whatever the server actually has, for a
        // reason that has nothing to do with the trip itself.
        persistenceController.save()
    }

    /// Fix 4: sign-out cleanup for the companions cache — see the protocol
    /// doc comment. A plain fetch + loop rather than an `NSBatchUpdateRequest`
    /// because a batch update writes straight to the SQL store and skips
    /// `viewContext`'s in-memory objects entirely; any `TripEntity` already
    /// faulted into memory (e.g. the trip currently on screen) would keep
    /// showing its stale `companionsJSON` until the next fetch. This runs
    /// once, at sign-out, so the per-row loop cost is a non-issue.
    func clearCompanionsCache() {
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "companionsJSON != nil")
        guard let entities = try? context.fetch(request), !entities.isEmpty else { return }
        for entity in entities {
            entity.companionsJSON = nil
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

    /// Photos of this trip whose ONLY copy is the server's.
    ///
    /// Asked immediately before the trip is taken off the server, because that
    /// removal destroys the server's blobs: anything in this list is about to
    /// stop existing anywhere unless it is pulled down first.
    func serverOnlyPhotoIds(tripId: UUID) -> [UUID] {
        let req: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
        req.predicate = NSPredicate(format: "trip.id == %@", tripId as CVarArg)
        guard let rows = try? context.fetch(req) else { return [] }
        return rows.compactMap { row -> UUID? in
            guard let id = row.id else { return nil }
            guard row.remoteURL != nil || row.thumbnailURL != nil else { return nil }
            let filename = row.filename ?? ""
            guard !PhotoStorageService.localFileExists(filename: filename) else { return nil }
            return id
        }
    }

    /// Points a photo row at a file this device now holds, and clears the
    /// server URLs it no longer has any claim to.
    func adoptRescuedPhoto(id: UUID, filename: String) {
        let req: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        guard let row = try? context.fetch(req).first else { return }
        row.filename = filename
        row.remoteURL = nil
        row.thumbnailURL = nil
        persistenceController.save()
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

    func addPhoto(
        to tripId: UUID, image: UIImage, caption: String?,
        capturedAt: Date? = nil, latitude: Double? = nil, longitude: Double? = nil
    ) -> TripPhoto? {
        guard let filename = PhotoStorageService.savePhoto(image, for: tripId),
              let entity = fetchEntity(id: tripId) else { return nil }

        let photoEntity = TripPhotoEntity(context: context)
        let photoId = UUID()
        photoEntity.id = photoId
        photoEntity.filename = filename
        photoEntity.caption = caption
        photoEntity.timestamp = Date()
        photoEntity.capturedAt = capturedAt
        photoEntity.exifLatitude = latitude.map(NSNumber.init(value:))
        photoEntity.exifLongitude = longitude.map(NSNumber.init(value:))
        photoEntity.lastModifiedAt = Date()
        photoEntity.sortOrder = Int16(entity.photos?.count ?? 0)
        photoEntity.trip = entity
        entity.lastModifiedAt = Date()
        persistenceController.save()

        let photo = TripPhoto(
            id: photoId, filename: filename, caption: caption, timestamp: Date(),
            capturedAt: capturedAt, exifLatitude: latitude, exifLongitude: longitude)
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

    // MARK: - Отметки на маршруте

    func addCheckpoint(_ checkpoint: TripCheckpoint, to tripId: UUID) -> TripCheckpoint? {
        guard let entity = fetchEntity(id: tripId) else { return nil }

        let ce = TripCheckpointEntity(context: context)
        ce.id = checkpoint.id
        ce.timestamp = checkpoint.timestamp
        ce.latitude = checkpoint.latitude
        ce.longitude = checkpoint.longitude
        ce.distanceFromStart = checkpoint.distanceFromStart
        ce.elapsedFromStart = checkpoint.elapsedFromStart
        ce.name = checkpoint.name
        ce.photoId = checkpoint.photoId
        ce.photoIdsJSON = Self.encodePhotoIds(checkpoint.photoIds)
        ce.placeId = checkpoint.placeId
        ce.createdAt = Date()
        ce.lastModifiedAt = Date()
        ce.userId = SettingsManager.shared.localUserId
        ce.trip = entity
        markCheckpointsChanged(on: entity)
        persistenceController.save()
        return checkpoint
    }

    /// Отметки едут внутри поездки, поэтому любая их правка — правка поездки:
    /// без флага `pendingUpload` очередь синка её не увидит, а следующий pull
    /// заменит локальный список серверным — то есть сотрёт отметку, которую
    /// человек только что поставил. Ревью 8 сентября нашло ровно это.
    private func markCheckpointsChanged(on entity: TripEntity) {
        entity.lastModifiedAt = Date()
        if Self.shouldFlipPendingUpload(for: entity) {
            entity.syncStatus = SyncStatus.pendingUpload.rawValue
        }
    }

    /// Прикреплённые снимки — JSON-массивом строк в одной колонке, как
    /// `stickersJSON` у поездки: связи с `TripPhotoEntity` нет нарочно, снимок
    /// может уехать с другого телефона позже, чем отметка.
    static func encodePhotoIds(_ ids: [UUID]) -> String? {
        guard !ids.isEmpty,
              let data = try? JSONEncoder().encode(ids.map(\.uuidString)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decodePhotoIds(_ json: String?) -> [UUID] {
        guard let json, let data = json.data(using: .utf8),
              let strings = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return strings.compactMap(UUID.init(uuidString:))
    }

    @discardableResult
    func updateCheckpoint(id: UUID, name: String?, photoId: UUID?, photoIds: [UUID]) -> UUID? {
        let request: NSFetchRequest<TripCheckpointEntity> = TripCheckpointEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        guard let ce = try? context.fetch(request).first else { return nil }
        ce.name = name
        ce.photoId = photoId
        ce.photoIdsJSON = Self.encodePhotoIds(photoIds)
        ce.lastModifiedAt = Date()
        if let trip = ce.trip { markCheckpointsChanged(on: trip) }
        persistenceController.save()
        return ce.trip?.id
    }

    @discardableResult
    func deleteCheckpoint(id: UUID) -> UUID? {
        let request: NSFetchRequest<TripCheckpointEntity> = TripCheckpointEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        guard let ce = try? context.fetch(request).first else { return nil }
        let tripId = ce.trip?.id
        if let trip = ce.trip { markCheckpointsChanged(on: trip) }
        context.delete(ce)
        persistenceController.save()
        return tripId
    }

    /// Снимок был обложкой или прикреплён к отметке — отметка остаётся,
    /// ссылка снимается. Без этого `photoId` указывал бы в пустоту, а карточка
    /// рисовала бы заглушку вместо снимка.
    private func detachPhotoFromCheckpoints(photoId: UUID) {
        let request: NSFetchRequest<TripCheckpointEntity> = TripCheckpointEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "photoId == %@ OR photoIdsJSON CONTAINS[c] %@",
            photoId as CVarArg, photoId.uuidString)
        for ce in (try? context.fetch(request)) ?? [] {
            if ce.photoId == photoId { ce.photoId = nil }
            let rest = Self.decodePhotoIds(ce.photoIdsJSON).filter { $0 != photoId }
            ce.photoIdsJSON = Self.encodePhotoIds(rest)
            ce.lastModifiedAt = Date()
        }
    }

    // MARK: - Места (0.6.8)

    func setPlaceId(forCheckpoint id: UUID, placeId: UUID) {
        let request: NSFetchRequest<TripCheckpointEntity> = TripCheckpointEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        guard let ce = try? context.fetch(request).first, ce.placeId != placeId else { return }
        // Нарочно без `markCheckpointsChanged`: место выводится из отметки и
        // трека, оба уже синхронизируются; взводить очередь ради выведенного
        // значения — слать каждую поездку библиотеки после первого бэкфилла.
        ce.placeId = placeId
        persistenceController.save()
    }

    func checkpointsWithoutPlace() -> [(checkpoint: TripCheckpoint, tripId: UUID)] {
        let request: NSFetchRequest<TripCheckpointEntity> = TripCheckpointEntity.fetchRequest()
        request.predicate = NSPredicate(format: "placeId == nil AND trip != nil AND trip.endDate != nil AND trip.syncStatus != %d",
                                        SyncStatus.pendingDelete.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        return ((try? context.fetch(request)) ?? []).compactMap { ce in
            guard let id = ce.id, let ts = ce.timestamp, let tripId = ce.trip?.id else { return nil }
            return (TripCheckpoint(id: id, timestamp: ts, latitude: ce.latitude, longitude: ce.longitude,
                                   distanceFromStart: ce.distanceFromStart, elapsedFromStart: ce.elapsedFromStart,
                                   name: ce.name, photoId: ce.photoId,
                                   photoIds: Self.decodePhotoIds(ce.photoIdsJSON), placeId: nil), tripId)
        }
    }

    func checkpointCoordinates(placeId: UUID) -> [CLLocationCoordinate2D] {
        let request: NSFetchRequest<TripCheckpointEntity> = TripCheckpointEntity.fetchRequest()
        request.predicate = NSPredicate(format: "placeId == %@", placeId as CVarArg)
        return ((try? context.fetch(request)) ?? []).map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    func tripPreviews(needingPlaceMatch: Bool) -> [TripPreviewRef] {
        let request = NSFetchRequest<NSDictionary>(entityName: "TripEntity")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id", "startDate", "previewPolyline"]
        var predicates = [completedTripPredicate]
        if needingPlaceMatch { predicates.append(NSPredicate(format: "placesMatchedAt == nil")) }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]
        return ((try? context.fetch(request)) ?? []).compactMap { row in
            guard let id = row["id"] as? UUID, let start = row["startDate"] as? Date else { return nil }
            return TripPreviewRef(id: id, startDate: start, previewPolyline: row["previewPolyline"] as? Data)
        }
    }

    func markPlacesMatched(tripId: UUID) { markPlacesMatched(tripIds: [tripId]) }

    func markPlacesMatched(tripIds: [UUID]) {
        guard !tripIds.isEmpty else { return }
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id IN %@", tripIds)
        let now = Date()
        // Одна выборка и ОДНО сохранение на всю пачку: сохранение контекста на
        // каждую поездку — это тысяча записей на диск на первой сверке.
        for e in (try? context.fetch(request)) ?? [] { e.placesMatchedAt = now }
        persistenceController.save()
    }

    func deletePhoto(id: UUID, from tripId: UUID) {
        detachPhotoFromCheckpoints(photoId: id)
        let request: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let entity = try? context.fetch(request).first {
            // Read BEFORE the row goes: this is the only moment anyone can
            // still tell whether the server holds a copy, and the enqueue gate
            // needs exactly that answer. A thumbnail counts — an upload that
            // got that far has a blob on the server to remove.
            let hadServerCopy = entity.remoteURL != nil || entity.thumbnailURL != nil
            PhotoStorageService.deletePhoto(filename: entity.filename ?? "")
            if let trip = entity.trip {
                trip.lastModifiedAt = Date()
            }
            context.delete(entity)
            persistenceController.save()
            Task { @MainActor in
                SyncEnqueuer.enqueue(
                    SyncOperation(entityType: .photo, entityId: id, action: .delete),
                    hasServerCopy: hadServerCopy
                )
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
            return TripPhoto(
                id: pid, filename: filename, caption: pe.caption, timestamp: ts,
                capturedAt: pe.capturedAt,
                exifLatitude: pe.exifLatitude?.doubleValue,
                exifLongitude: pe.exifLongitude?.doubleValue
            )
        } ?? []

        let checkpoints: [TripCheckpoint] = (entity.checkpoints?.array as? [TripCheckpointEntity])?
            .compactMap { ce in
                guard let cid = ce.id, let ts = ce.timestamp else { return nil }
                return TripCheckpoint(
                    id: cid, timestamp: ts,
                    latitude: ce.latitude, longitude: ce.longitude,
                    distanceFromStart: ce.distanceFromStart,
                    elapsedFromStart: ce.elapsedFromStart,
                    name: ce.name, photoId: ce.photoId,
                    photoIds: Self.decodePhotoIds(ce.photoIdsJSON), placeId: ce.placeId
                )
            }
            .sorted { $0.elapsedFromStart < $1.elapsedFromStart } ?? []

        let badgeIds: [String]
        if let json = entity.badgesJSON,
           let data = json.data(using: .utf8),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            badgeIds = ids
        } else {
            badgeIds = []
        }

        let companions: [TripCompanion]
        if let json = entity.companionsJSON,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([TripCompanion].self, from: data) {
            companions = decoded
        } else {
            companions = []
        }

        return Trip(
            id: id, startDate: startDate, endDate: entity.endDate,
            distance: entity.distance, maxSpeed: entity.maxSpeed,
            averageSpeed: entity.averageSpeed, trackPoints: points, photos: photos,
            checkpoints: checkpoints,
            title: entity.title, titleIsCustom: entity.titleIsCustom,
            tripDescription: entity.tripDescription,
            fuelUsed: entity.fuelUsed, elevation: entity.elevation,
            region: entity.region, isPrivate: entity.isPrivate,
            isTransfer: entity.isTransfer,
            vehicleId: entity.vehicleId, fuelCurrency: entity.fuelCurrency,
            previewPolyline: entity.previewPolyline, earnedBadgeIds: badgeIds,
            xpEarned: Int(entity.xpEarned),
            companions: companions, isOnServer: entity.serverCreatedAt != nil
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
        // `pendingDelete` belongs in this guard as much as `pendingUpload`.
        // 0.6.1 forces one full pull on every device, and on a full pull a
        // soft-deleted trip is still a live server row — without this it would
        // be rewritten to `.synced` and the user's deliberate deletion undone
        // by the upgrade itself.
        if entity.id != nil,
           entity.syncStatus == SyncStatus.pendingUpload.rawValue
            || entity.syncStatus == SyncStatus.pendingDelete.rawValue,
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
        // ТОЛЬКО когда сервер прислал ключ. `?? false` читал отсутствие поля
        // как явное «не трансфер», и пул со старого бэкенда молча откатывал
        // пометку «ехал пассажиром» — машина при этом уже снята, и поездка
        // оставалась без того и без другого.
        if let remoteTransfer = p.isTransfer { entity.isTransfer = remoteTransfer }
        entity.fuelCurrency = p.fuelCurrency
        entity.previewPolyline = p.previewPolyline.flatMap { Data(base64Encoded: $0) }
        // Кэш держал старую форму до перезапуска приложения.
        Trip.invalidatePreviewCache(for: p.id)
        entity.badgesJSON = p.badgesJson
        entity.xpEarned = Int32(p.xpEarned ?? 0)
        entity.conflictVersion = Int32(p.conflictVersion)
        entity.lastModifiedAt = p.lastModifiedAt
        // "This local row mirrors a server row" — the fact the tombstone guard
        // in `PullApplier` reads. Set once and never overwritten: an older
        // server omits the field, and `markUnpublished` clears it on purpose,
        // so a later pull must not quietly re-assert what the user unpublished.
        if entity.serverCreatedAt == nil {
            entity.serverCreatedAt = p.serverCreatedAt ?? p.lastModifiedAt
        }
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
            let serverById = Dictionary((p.photos ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for pe in localPhotos {
                guard let pid = pe.id else { continue }
                if pe.uploadStatus == PhotoUploadStatus.localOnly.rawValue {
                    continue
                }
                if !serverIds.contains(pid) {
                    context.delete(pe)
                    continue
                }
                // Время и место съёмки — ТОЛЬКО когда сервер их прислал и у нас
                // их нет: локальные значения точнее (взяты из PHAsset в момент
                // выбора), а старый сервер ключей не шлёт вовсе.
                if let remote = serverById[pid] {
                    if pe.capturedAt == nil, let at = remote.capturedAt { pe.capturedAt = at }
                    if pe.exifLatitude == nil, let lat = remote.exifLatitude, let lon = remote.exifLongitude {
                        pe.exifLatitude = NSNumber(value: lat)
                        pe.exifLongitude = NSNumber(value: lon)
                    }
                }
            }
        }

        // Отметки: сервер прислал список — он и есть правда. Ключ отсутствует —
        // старый сервер, локальные не трогаем (иначе каждый pull стирал бы их).
        if let serverCheckpoints = p.checkpoints {
            // Место выводится локально и на сервер не уезжает, поэтому в
            // пришедшем списке `placeId` пуст почти всегда. Правило 0.6.5 про
            // `capturedAt`/`exifLatitude` ровно про этот случай: локальное
            // значение точнее серверного и не перезаписывается. Иначе каждый
            // пул осиротил бы отметки, сверка зарегистрировала бы их заново — и
            // УДАЛЁННОЕ место воскресало бы с полной историей.
            var previous: [UUID: UUID] = [:]
            if let existing = entity.checkpoints?.array as? [TripCheckpointEntity] {
                for ce in existing {
                    if let cid = ce.id, let pid = ce.placeId { previous[cid] = pid }
                    context.delete(ce)
                }
            }
            for c in serverCheckpoints.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                let ce = TripCheckpointEntity(context: context)
                ce.id = c.id
                ce.timestamp = c.timestamp
                ce.latitude = c.latitude
                ce.longitude = c.longitude
                ce.distanceFromStart = c.distanceFromStart
                ce.elapsedFromStart = c.elapsedFromStart
                ce.name = c.name
                ce.photoId = c.photoId
                ce.photoIdsJSON = Self.encodePhotoIds(c.photoIds ?? [])
                ce.placeId = c.placeId ?? previous[c.id]
                ce.createdAt = Date()
                ce.lastModifiedAt = p.lastModifiedAt
                ce.userId = SettingsManager.shared.localUserId
                ce.trip = entity
            }
        }

        // Save deferred to PullApplier.flushPendingApplies() — batches a
        // /sync/pull's worth of writes into a single CoreData save call.
    }

    func applyRemoteVehicle(_ p: VehicleSyncPayload) {
        let req: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", p.id as CVarArg)
        req.fetchLimit = 1
        let existing = try? context.fetch(req).first
        let entity = existing ?? VehicleEntity(context: context)
        // Есть ли на этом устройстве правки, которые ещё не уехали. Считается
        // ДО присваиваний и только для уже существующей строки: у новой
        // `syncStatus` равен нулю (`pendingUpload`) по умолчанию, и без этой
        // оговорки ни одна приехавшая машина не применилась бы вовсе.
        //
        // Это защита от гонки «фоновый пул обогнал очередь», а НЕ замок: если
        // правка честно проиграла конфликт, флаг с неё снимает
        // `APISyncTransport.pullAndOverwriteVehicle` — и тогда сюда приезжает
        // серверная версия целиком, включая четыре оси видимости ниже. Пока
        // обе двери были закрыты одновременно (здесь `hasLocalEdits`, а
        // конфликт при загрузке молча проглатывался), машина после конфликта не
        // уезжала и не обновлялась никогда.
        let hasLocalEdits = existing?.syncStatus == SyncStatus.pendingUpload.rawValue
        entity.id = p.id
        entity.name = p.name
        entity.avatarEmoji = p.avatarEmoji
        // Absent is not «car» — it is the server declining to have an opinion,
        // and the two have to be told apart the same way the five optional
        // fields below tell them apart. Reading absence as «car» meant every
        // pull reset the silhouette this device had just set, including the
        // pull that immediately follows uploading it: pick a scooter, sync,
        // watch it turn back into a saloon. No backend has the column yet, so
        // that was every pull for every signed-in person.
        if let style = p.avatarStyle { entity.avatarStyle = style }
        entity.odometerKm = p.odometerKm
        // Только когда ключ пришёл: сервер без колонки его не шлёт, и `?? nil`
        // стёр бы введённое человеком число. Без этой строки ручной пробег
        // уезжал на сервер и не возвращался — терялся при переустановке и не
        // доезжал на второй телефон.
        if p.manualOdometerKnown {
            // Ключ пришёл: значение ИЛИ явный null. Второе — это очистка,
            // сделанная на другом устройстве, и её надо применить.
            entity.manualOdometerKm = p.manualOdometerKm.map { NSNumber(value: $0) }
        }
        entity.vehicleLevel = Int32(p.level)
        entity.stickersJSON = p.stickersJson
        entity.cityConsumption = p.cityConsumption
        entity.highwayConsumption = p.highwayConsumption
        entity.fuelPrice = p.fuelPrice
        // A server that predates these columns sends nothing back, and nothing
        // is not "reset to default" — keep whatever this device already knows.
        if let type = p.vehicleType { entity.vehicleType = type }
        if let plate = p.plate { entity.plate = plate }
        // Четыре оси видимости — единственные поля, где ответ сервера НЕ
        // главнее локального. Человек мог выключить показ машины в самолёте
        // или в момент, когда очередь стоит в бэкоффе; следующий пул возвращал
        // флаг обратно, а экран честно показывал возвращённое значение — то
        // есть приватное решение отменялось молча и без следа. Пока правка не
        // уехала, побеждает она. Остальные поля этой оговорки не получают:
        // вернувшееся название машины — досада, вернувшаяся видимость — утечка.
        if !hasLocalEdits, let plateVisible = p.plateVisible { entity.plateVisible = plateVisible }
        if !hasLocalEdits, let visible = p.visibleToOthers { entity.visibleToOthers = visible }
        if let currency = p.fuelCurrency { entity.fuelCurrency = currency }
        // Единица приборки — по тому же правилу «сказано / не сказано», и
        // цена молчания здесь выше всех: без этой строки поле не доживает до
        // второго телефона и до переустановки, а теряется не символ, а
        // ОДОМЕТР. Приложение в милях разберёт введённые с километровой панели
        // 142 000 как 228 527 — и не покажет ни одного противоречия, потому
        // что при открытии переведёт их обратно в те же 142 000.
        //
        // `nil` здесь значит и «старый сервер молчит», и «значение, которого
        // мы не знаем»: и то и другое — не мнение, а отсутствие мнения.
        // Подменить неизвестное на `app` было бы той самой поломкой, ради
        // которой поле заведено: у машины могло лежать осознанное `metric`, и
        // километровая панель молча переехала бы в единицы приложения.
        //
        // И `hasLocalEdits` — пятым к четырём осям видимости, а не шестым к
        // имени и пробегу. Разбор «досада или утечка» здесь даёт третий ответ:
        // вернувшаяся единица приборки — это НЕВЕРНОЕ ЧИСЛО В БАЗЕ. Человек
        // выбирает «километры» в самолёте, полный пул (0.6.1 заказывает такой
        // на каждом устройстве, у которого не совпал штамп хранилища)
        // обгоняет очередь и возвращает `app`, поле ввода снова разбирает
        // мили — и списанные с панели 142 000 уезжают в базу как 228 527.
        // Пока правка не уехала, побеждает она.
        if !hasLocalEdits, let units = p.dashboardUnits { entity.dashboardUnits = units.rawValue }
        // Паспорт (0.6.4) — по тому же правилу: ключ пришёл, значит сервер
        // имеет мнение; не пришёл — молчит, и локальное трогать нельзя.
        if let about = p.about { entity.about = about }
        if let make = p.make { entity.make = make }
        if let model = p.model { entity.model = model }
        if let year = p.year { entity.year = Int32(year) }
        if let body = p.bodyType { entity.bodyType = body }
        if !hasLocalEdits, let mapVisible = p.mapVisible { entity.mapVisible = mapVisible }
        if !hasLocalEdits, let photosVisible = p.photosVisible { entity.photosVisible = photosVisible }
        if let archived = p.isArchived { entity.isArchived = archived }
        // `soldAt` — исключение: здесь nil ЗНАЧИМ, это «продажу отменили».
        // Отличаем по наличию КЛЮЧА, а не по значению: старый сервер про поле
        // молчит (тогда локальное не трогаем), новый присылает `null` (тогда
        // снимаем продажу). Раньше здесь стояло `if let`, и отмена продажи с
        // другого устройства не приезжала никогда.
        if p.soldAtKnown { entity.soldAt = p.soldAt }
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

    /// The server is authoritative for preferences but NOT for progress.
    ///
    /// Two facts make the naive "assign everything" version dangerous. The
    /// backend applies its `last_modified_at > since` filter only `if (since)`,
    /// so a FULL pull always carries the settings row — and 0.6.1 forces one
    /// full pull on every device when the store-identity stamp finds no match.
    /// And the local row is routinely AHEAD of the server with no pending
    /// marker: `GamificationManager` only arms a five-second in-memory timer,
    /// which dies with the process, and `recoverPendingEntities` looks for
    /// `pendingUpload`, so it never resurrects the settings row.
    ///
    /// Progress is therefore merged monotonically — XP, level and best streak
    /// only ever go up — and preferences follow `lastModifiedAt`. Without this
    /// the 0.6.1 upgrade would have zeroed the whole fleet's level in one day,
    /// which is the same failure the release exists to fix, pointed the other
    /// way.
    ///
    /// Правило «preferences follow `lastModifiedAt`» до 0.6.7 работало вхолостую
    /// в одну сторону: отметку времени на строке настроек ставил ТОЛЬКО сервер
    /// (`saveSettings` её не трогал), поэтому свежая местная правка выглядела
    /// прошлогодней и любой пул её затирал. Отметку теперь ставит `saveSettings`
    /// — и именно она, а не флаг `syncStatus`, отличает здесь «правку, ждущую
    /// отправки» от «своей же старой копии». Флаг бы не подошёл: у строки
    /// настроек он равен нулю (`pendingUpload`) с рождения, и первый же пул на
    /// новом телефоне не применился бы вовсе — то есть восстановление
    /// аккаунта. Держит `SettingsUnitWireTests`.
    func applyRemoteSettings(_ p: SettingsSyncPayload) {
        let req: NSFetchRequest<UserSettingsEntity> = UserSettingsEntity.fetchRequest()
        req.fetchLimit = 1
        let existing = try? context.fetch(req).first
        let entity = existing ?? UserSettingsEntity(context: context)

        // Progress never decreases. A server that has not heard from this
        // phone since before the last drive is behind, not right.
        entity.profileXP = max(entity.profileXP, Int64(p.profileXp))
        entity.profileLevel = max(entity.profileLevel, Int32(p.profileLevel))
        entity.bestStreak = max(entity.bestStreak, Int32(p.bestStreak))

        // Preferences and the fields that are mutable by nature: newest wins.
        // `id` lives in here on purpose — rewriting it from a STALE row
        // re-points `localUserId`, the identity every entity is stamped with.
        let localStamp = entity.lastModifiedAt ?? .distantPast
        if existing == nil || p.lastModifiedAt >= localStamp {
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
            entity.currentStreak = Int32(p.currentStreak)
            entity.lastTripDate = p.lastTripDate
            entity.lastModifiedAt = p.lastModifiedAt
        }

        entity.conflictVersion = Int32(p.conflictVersion)
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
            // Три вызывающих — `deleteTrip` (короткое замыкание), транспорт
            // при `tripNotFound` на загрузке и транспорт после подтверждения
            // удаления — все проходят здесь; проезды без связи с поездкой
            // каскад не заберёт.
            CoreDataPlaceStore(context: context).deletePasses(tripId: id)
            let vehicleId = e.vehicleId
            // Каскад забирает строки снимков, но не сами кадры: они лежат
            // файлами в `Documents/TripPhotos/<id>/`, и каталог исключён из
            // резервной копии. Убрать их умел только `purgeSoftDeletedTrips`,
            // а сюда приходят три пути мимо него — своё удаление поездки, ещё
            // не доехавшей до сервера, и два подтверждения удаления с
            // сервера, — то есть кадры оставались на диске насовсем.
            PhotoStorageService.deletePhotos(for: id)
            context.delete(e)
            if let vehicleId { recomputeOdometers(forVehicles: [vehicleId]) }
            saveIfNeeded()
        }
    }

    /// Applies a server tombstone, but only to a trip this device actually
    /// mirrors from the server.
    ///
    /// `serverCreatedAt == nil` means one of two things, and both forbid the
    /// delete: the trip only ever existed on this phone, or the user
    /// un-published it — `markUnpublished` clears the column on purpose, and
    /// "gone from the server, kept here" is precisely what un-publishing means.
    /// Without this guard a tombstone meant for the server's copy destroys the
    /// local original, which is how a privacy migration could take a library
    /// with it.
    /// - Returns: true when the trip was actually deleted.
    @discardableResult
    func deleteTripHardIfMirrored(id: UUID) -> Bool {
        guard let entity = fetchEntity(id: id) else { return false }
        guard entity.serverCreatedAt != nil else {
            Logger(subsystem: "com.triptrack", category: "core-data")
                .notice("tombstone ignored — trip is not mirrored from the server")
            return false
        }
        // Та же уборка, что и в `deleteTripHard`: надгробие с другого телефона
        // тоже означает «поездки больше нет», а кадры каскад не заберёт.
        CoreDataPlaceStore(context: context).deletePasses(tripId: id)
        PhotoStorageService.deletePhotos(for: id)
        context.delete(entity)
        saveIfNeeded()
        return true
    }

    /// The trip a photo belongs to, so `PullApplier` can skip a photo tombstone
    /// whose parent trip it just refused to delete.
    func tripId(forPhoto id: UUID) -> UUID? {
        let req: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return (try? context.fetch(req).first)?.trip?.id
    }

    /// Recomputes the odometer of the named vehicles from the trips assigned
    /// to them, and their level from the result.
    ///
    /// The odometer used to be a pure accumulator — `+= trip.distanceKm` once,
    /// when a trip finished, and never revisited. Everything that can change
    /// the trips underneath it therefore drifted it: moving a trip to another
    /// car left the kilometres behind, deleting a trip left them credited, and
    /// a library restored from the server never reached the garage at all. A
    /// real user reported the first of those and was sitting on all three.
    ///
    /// Deriving it instead of accumulating it makes every one of those correct
    /// by construction. Soft-deleted trips are excluded, because from the
    /// user's point of view they are gone.
    func recomputeOdometers(forVehicles vehicleIds: [UUID]) {
        for vehicleId in Set(vehicleIds) {
            let req: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
            // Трансферы не наматывают машину — то же правило, что в
            // `VehicleOdometer`. Два места, считающие ОДНО число по разным
            // правилам, однажды разойдутся молча: сюда можно попасть из
            // `applyRemoteTrip`, который ставит `vehicleId` и `isTransfer`
            // независимо друг от друга.
            req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                completedTripPredicate,
                NSPredicate(format: "vehicleId == %@", vehicleId as CVarArg),
                NSPredicate(format: "isTransfer == NO"),
            ])
            let metres = (try? context.fetch(req))?.reduce(0.0) { $0 + $1.distance } ?? 0
            let km = metres / 1000

            let vReq: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
            vReq.predicate = NSPredicate(format: "id == %@", vehicleId as CVarArg)
            vReq.fetchLimit = 1
            guard let vehicle = try? context.fetch(vReq).first else { continue }
            vehicle.odometerKm = km
            vehicle.vehicleLevel = Int32(VehicleLevelSystem.level(for: km))
        }
    }

    /// Recomputes every vehicle — used after the library changes wholesale,
    /// i.e. once trips come home from the server.
    ///
    /// Refuses to run on an empty library. With no trips the odometers are not
    /// evidence of drift, they are the only surviving record of the mileage —
    /// zeroing them there would repeat exactly the mistake this release exists
    /// to fix.
    func recomputeAllVehicleOdometers() {
        guard countLiveTrips() > 0 else { return }
        let req: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        let ids = ((try? context.fetch(req)) ?? []).compactMap { $0.id }
        recomputeOdometers(forVehicles: ids)
        saveIfNeeded()
    }

    /// Every trip row that exists, whatever its sync status — including
    /// `pendingDelete`, which still mirrors a live server row.
    ///
    /// This measures LIBRARY SIZE, not sync progress, and the distinction is
    /// load-bearing: `markAllPendingUpload()` flips every trip to
    /// `pendingUpload` during first sign-in and when Cloud Sync is switched on,
    /// and both then run a pull. A heal detector counting `synced` rows would
    /// read "server has everything, I have nothing" at exactly that moment and
    /// start healing the device against itself.
    func countLiveTrips() -> Int {
        let req: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        req.predicate = NSPredicate(format: "endDate != nil")
        return (try? context.count(for: req)) ?? 0
    }

    func deleteVehicleHard(id: UUID) {
        let req: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let e = try? context.fetch(req).first {
            context.delete(e)
            saveIfNeeded()
        }
    }

    /// «Отправлено и подтверждено»: снимает `pendingUpload` и берёт версию
    /// сервера. Полей машины не трогает — их и незачем, когда сервер принял
    /// именно то, что мы послали. При КОНФЛИКТЕ этого мало: содержимое-то у
    /// сервера другое, поэтому там за ним сразу идёт `applyRemoteVehicle`
    /// (см. `APISyncTransport.pullAndOverwriteVehicle`).
    func markVehicleSynced(id: UUID, conflictVersion: Int) {
        let req: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let e = try? context.fetch(req).first else { return }
        e.syncStatus = SyncStatus.synced.rawValue
        e.conflictVersion = Int32(conflictVersion)
        persistenceController.save()
    }

    func deletePhotoHard(id: UUID) {
        detachPhotoFromCheckpoints(photoId: id)
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

    // MARK: - Journeys (0.6.6)

    private func journeyEntity(id: UUID) -> JourneyEntity? {
        let req: NSFetchRequest<JourneyEntity> = JourneyEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try? context.fetch(req).first
    }

    private func journey(from e: JourneyEntity) -> Journey? {
        guard let id = e.id, let start = e.startDate else { return nil }
        return Journey(
            id: id, userId: e.userId, title: e.title, startDate: start, endDate: e.endDate,
            excludedTripIds: Self.decodePhotoIds(e.excludedTripIdsJSON),
            coverPhotoId: e.coverPhotoId, isPrivate: e.isPrivate,
            conflictVersion: Int(e.conflictVersion),
            lastModifiedAt: e.lastModifiedAt ?? Date(), serverCreatedAt: e.serverCreatedAt)
    }

    func fetchJourneys() -> [Journey] {
        let req: NSFetchRequest<JourneyEntity> = JourneyEntity.fetchRequest()
        req.predicate = NSPredicate(format: "syncStatus != %d", SyncStatus.pendingDelete.rawValue)
        req.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]
        return ((try? context.fetch(req)) ?? []).compactMap(journey(from:))
    }

    func fetchJourney(id: UUID) -> Journey? { journeyEntity(id: id).flatMap(journey(from:)) }

    @discardableResult
    func saveJourney(_ j: Journey) -> Journey {
        let e = journeyEntity(id: j.id) ?? {
            let n = JourneyEntity(context: context)
            n.id = j.id
            n.createdAt = Date()
            n.userId = SettingsManager.shared.localUserId
            return n
        }()
        e.title = j.title
        e.startDate = j.startDate
        e.endDate = j.endDate
        e.excludedTripIdsJSON = Self.encodePhotoIds(j.excludedTripIds)
        e.coverPhotoId = j.coverPhotoId
        e.isPrivate = j.isPrivate
        e.lastModifiedAt = Date()
        // Личные данные, как машина: уезжают только при включённом облаке,
        // но флаг взводим всегда — очередь сама решит, слать ли.
        e.syncStatus = SyncStatus.pendingUpload.rawValue
        persistenceController.save()
        return journey(from: e) ?? j
    }

    func markJourneyDeleted(id: UUID) {
        guard let e = journeyEntity(id: id) else { return }
        e.syncStatus = SyncStatus.pendingDelete.rawValue
        e.lastModifiedAt = Date()
        persistenceController.save()
    }

    func deleteJourneyHard(id: UUID) {
        guard let e = journeyEntity(id: id) else { return }
        context.delete(e)
        persistenceController.save()
    }

    func journeySyncStatus(id: UUID) -> Int16? { journeyEntity(id: id)?.syncStatus }

    /// `fetchEntity` — не `fetchTripDetail`: только старт нужен для проверки
    /// окна, а `fetchTripDetail` заодно материализует весь трек поездки.
    func journeyContaining(tripId: UUID) -> Journey? {
        guard let start = fetchEntity(id: tripId)?.startDate else { return nil }
        return fetchJourneys().first { $0.contains(tripId: tripId, startDate: start) }
    }

    func journeyOverlapping(start: Date, end: Date?, excluding: UUID?) -> Journey? {
        let far = Date.distantFuture
        return fetchJourneys().first { j in
            guard j.id != excluding else { return false }
            return j.startDate <= (end ?? far) && start <= (j.endDate ?? far)
        }
    }

    /// Плечи — свои поездки в окне, по времени старта. Трансферы входят: едет
    /// человек, не машина.
    ///
    /// Окно отрезает БАЗА, а не фильтр в памяти: `fetchAllTrips()` поднимал всю
    /// библиотеку — тысячу поездок за пять лет — ради шести внутри недели, и
    /// делал это на каждый вход в экран, на каждое «убрать плечо» и на каждую
    /// перерисовку карточки. Снятые галочки (`excludedTripIds`) остаются в
    /// памяти: их горстка, и правило членства всё равно живёт в одном месте —
    /// `Journey.contains`.
    func trips(in journey: Journey) -> [Trip] {
        var predicates = [
            completedTripPredicate,
            NSPredicate(format: "startDate >= %@", journey.startDate as NSDate),
        ]
        // Открытое окно (`endDate == nil`) тянется вперёд до конца времён —
        // верхней границы у запроса тогда нет вовсе.
        if let end = journey.endDate {
            predicates.append(NSPredicate(format: "startDate <= %@", end as NSDate))
        }
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TripEntity.startDate, ascending: true)]
        request.fetchBatchSize = 25
        guard let entities = try? context.fetch(request) else { return [] }
        return entities
            .compactMap { tripFromEntity($0, includeTrackPoints: false) }
            .filter { journey.contains($0) }
    }

    func applyRemoteJourney(_ p: JourneySyncPayload) {
        let existing = journeyEntity(id: p.id)
        // Локальная правка, которая ещё не уехала, старше серверной копии.
        //
        // Это защита от гонки «фоновый пул обогнал очередь», а НЕ замок: если
        // правка честно проиграла конфликт, флаг с неё снимает
        // `APISyncTransport.pullAndOverwriteJourney` — и тогда серверная версия
        // приезжает сюда и применяется. Пока обе двери были закрыты
        // одновременно (здесь guard, а конфликт при загрузке молча проглатывался),
        // путешествие после конфликта не уезжало и не обновлялось никогда.
        if existing?.syncStatus == SyncStatus.pendingUpload.rawValue { return }
        // Удалённое здесь и ещё не подтверждённое сервером — тем более: pull
        // приходит из того же обмена, в котором DELETE только стоит в очереди,
        // и без этой строки путешествие ВОСКРЕСАЛО бы, вернувшись строкой
        // `synced`, — а очередь потом сносила бы его во второй раз, уже с
        // мигающей карточкой в «Моих».
        if existing?.syncStatus == SyncStatus.pendingDelete.rawValue { return }
        let e = existing ?? { let n = JourneyEntity(context: context); n.id = p.id; n.createdAt = Date(); return n }()
        e.userId = SettingsManager.shared.localUserId
        e.title = p.title; e.startDate = p.startDate; e.endDate = p.endDate
        e.excludedTripIdsJSON = Self.encodePhotoIds(p.excludedTripIds)
        e.coverPhotoId = p.coverPhotoId; e.isPrivate = p.isPrivate
        e.conflictVersion = Int32(p.conflictVersion)
        e.lastModifiedAt = p.lastModifiedAt
        e.serverCreatedAt = p.serverCreatedAt ?? e.serverCreatedAt ?? Date()
        e.syncStatus = SyncStatus.synced.rawValue
        // Сохранение — в PullApplier.flushPendingApplies(), как у всех.
    }

    /// «Отправлено и подтверждено»: снимает `pendingUpload` и берёт версию
    /// сервера. Полей записи не трогает — их и незачем, когда сервер принял
    /// именно то, что мы послали. При КОНФЛИКТЕ этого мало: содержимое-то у
    /// сервера другое, поэтому там за ним сразу идёт `applyRemoteJourney`
    /// (см. `APISyncTransport.pullAndOverwriteJourney`).
    func markJourneySynced(id: UUID, conflictVersion: Int) {
        guard let e = journeyEntity(id: id) else { return }
        e.syncStatus = SyncStatus.synced.rawValue
        e.conflictVersion = Int32(conflictVersion)
        e.serverCreatedAt = e.serverCreatedAt ?? Date()
        persistenceController.save()
    }
}
