import Foundation
import UIKit
import CoreData
import OSLog

/// Photo-upload lifecycle diagnostics. The original upload used to fail SILENTLY
/// (swallowed catch) which is exactly why "photos won't upload / only thumb on
/// server" was undiagnosable. `.notice` so the per-photo trail is exported.
private let photoLog = Logger(subsystem: "com.triptrack", category: "photo-upload")

struct TripUpsertResponse: Codable {
    let id: UUID
    let conflictVersion: Int
    let serverCreatedAt: Date
}

struct TripDetailRequest: Codable {
    let id: UUID
    let includeTrackPoints: Bool
}

struct TripDeleteRequest: Codable {
    let id: UUID
    let conflictVersion: Int
}

struct VehicleUpsertResponse: Codable {
    let id: UUID
    let conflictVersion: Int
}

struct VehicleDeleteRequest: Codable {
    let id: UUID
}

struct SettingsUpsertResponse: Codable {
    let conflictVersion: Int
}

@MainActor
final class APISyncTransport: SyncTransport {
    static let shared = APISyncTransport()

    private let client: APIClient
    private let photos: R2PhotoStorage
    private let repo: TripRepository

    init(client: APIClient = APIClient.shared, photos: R2PhotoStorage = R2PhotoStorage.shared, repo: TripRepository = CoreDataTripRepository()) {
        self.client = client
        self.photos = photos
        self.repo = repo
    }

    func execute(_ operation: SyncOperation) async throws {
        switch (operation.entityType, operation.action) {
        case (.trip, .upload), (.trip, .update):
            try await uploadTrip(id: operation.entityId)
        case (.trip, .delete):
            try await deleteTrip(id: operation.entityId)
        case (.trip, .unpublish):
            try await unpublishTrip(id: operation.entityId)
        case (.vehicle, .upload), (.vehicle, .update):
            try await uploadVehicle(id: operation.entityId)
        case (.vehicle, .delete):
            try await deleteVehicle(id: operation.entityId)
        case (.vehicle, .unpublish):
            break  // vehicles are never publishable on their own
        case (.photo, .upload), (.photo, .update):
            try await uploadPhoto(id: operation.entityId)
        case (.photo, .delete):
            try await deletePhoto(id: operation.entityId)
        case (.photo, .unpublish):
            break  // photo unpublish rides along with the parent trip's unpublish
        case (.settings, .upload), (.settings, .update):
            try await uploadSettings()
        case (.settings, .delete), (.settings, .unpublish):
            break
        }
    }

    // MARK: Trip

    private func uploadTrip(id: UUID) async throws {
        // Light entity read for the privacy re-gate only — no track-point decode.
        guard let entity = repo.fetchEntity(id: id) else { return }
        // Re-check the privacy gate at execute time. SyncEnqueuer's gate
        // fires at enqueue, but the op can sit in the queue across rapid
        // user toggles. Cloud Sync ON bypasses (full mirror).
        if !SettingsManager.shared.cloudSyncEnabled && entity.isPrivate {
            // If the trip already has a server copy, demoting locally
            // isn't enough — we need to strip the server side too.
            // Schedule an unpublish instead of just dropping the op.
            if entity.serverCreatedAt != nil {
                try await unpublishTrip(id: id)
            } else {
                entity.syncStatus = SyncStatus.synced.rawValue
                try? PersistenceController.shared.container.viewContext.save()
            }
            return
        }
        // Build the payload (decode all track points + movement-split + photo
        // metadata) on a BACKGROUND context — this was the residual main-thread
        // cost on long trips during a drain. nil = the trip vanished between the
        // gate and the build (deleted mid-drain) → drop the op.
        guard let payload = await repo.fetchTripSyncPayloadAsync(id: id) else { return }
        do {
            let res: TripUpsertResponse = try await client.post(APIEndpoint.tripUpsert, body: payload)
            repo.markSynced(tripId: id, conflictVersion: res.conflictVersion, serverCreatedAt: res.serverCreatedAt)
        } catch let err as APIError {
            if case .conflictDetected = err {
                try await pullAndOverwriteTrip(id: id)
            } else if case .tripNotFound = err {
                // The trip used to exist on the server but is now gone — the account
                // was reset, the trip was deleted elsewhere, or this ID belongs to
                // another user (stale local cache). Server is authoritative for synced
                // content, so we purge the local copy to stop the retry loop.
                repo.deleteTripHard(id: id)
            } else {
                throw err
            }
        }
    }

    /// Batch trip upload via `/sync/push`. Builds payloads off the main actor,
    /// chunks them under the 25 MB body limit, and POSTs each chunk. Returns the
    /// entityIds it fully handled (synced or conflict-resolved). Anything not
    /// returned — a privacy-skip, a chunk that failed, or a trip that vanished —
    /// is left for `SyncQueue`'s per-op `execute()` to drain, so this can never
    /// drop an op. Mirrors `uploadTrip`'s privacy gate + markSynced/conflict
    /// semantics, just amortized across many trips.
    func uploadTripsBatch(_ operations: [SyncOperation], onChunkSynced: @escaping @MainActor (Int) -> Void) async -> Set<UUID> {
        var handled = Set<UUID>()
        // Streaming chunker: build + POST one chunk at a time (instead of
        // building ALL payloads up front), so (a) memory stays bounded to one
        // chunk's track points and (b) progress advances per chunk via
        // onChunkSynced rather than jumping 0→N at the very end.
        let maxTripsPerChunk = 25
        let maxPointsPerChunk = 80_000
        var current: [TripSyncPayload] = []
        var points = 0

        func flush() async {
            guard !current.isEmpty else { return }
            let chunk = current
            current = []
            points = 0
            do {
                let res: SyncPushResponse = try await client.post(
                    APIEndpoint.syncPush, body: SyncPushRequest(trips: chunk))
                var synced = 0
                for r in res.trips ?? [] {
                    switch r.status {
                    case "created", "updated":
                        if let serverCreatedAt = r.serverCreatedAt {
                            repo.markSynced(tripId: r.id, conflictVersion: r.conflictVersion,
                                            serverCreatedAt: serverCreatedAt)
                        } else {
                            repo.markSynced(tripId: r.id, conflictVersion: r.conflictVersion)
                        }
                        handled.insert(r.id)
                        synced += 1
                    case "conflict":
                        // Resolve like the per-op path (pull + overwrite local) —
                        // but only mark handled if the pull SUCCEEDS. If it throws
                        // (network/5xx), leave the op queued so per-op execute()
                        // retries it and parks it in failedQueue (retry + user
                        // visibility) instead of silently dropping an unresolved
                        // conflict.
                        do {
                            try await pullAndOverwriteTrip(id: r.id)
                            handled.insert(r.id)
                            synced += 1
                        } catch {
                            // leave unhandled → per-op fallback
                        }
                    default:
                        break  // unknown status → leave for per-op execute()
                    }
                }
                // Trips the server didn't acknowledge stay unhandled → per-op.
                if synced > 0 { onChunkSynced(synced) }
            } catch {
                // Whole chunk failed (network/5xx) — none handled; per-op retries.
            }
        }

        for op in operations {
            let id = op.entityId
            guard let entity = repo.fetchEntity(id: id) else {
                // Trip gone (deleted mid-drain) — nothing to upload; drop the op
                // and count it as progress so the counter still reaches the total.
                handled.insert(id)
                onChunkSynced(1)
                continue
            }
            // Privacy re-gate (mirrors uploadTrip). A private trip with Cloud
            // Sync OFF must NOT go out in a batch — leave it for per-op
            // execute(), which runs the unpublish / mark-synced edge logic.
            if !SettingsManager.shared.cloudSyncEnabled && entity.isPrivate {
                continue
            }
            guard let payload = await repo.fetchTripSyncPayloadAsync(id: id) else {
                continue  // vanished between gate and build → leave for per-op
            }
            // Flush BEFORE appending when this trip would overflow the chunk.
            if !current.isEmpty,
               current.count >= maxTripsPerChunk || points + (payload.trackPoints?.count ?? 0) > maxPointsPerChunk {
                await flush()
            }
            current.append(payload)
            points += payload.trackPoints?.count ?? 0
        }
        await flush()
        return handled
    }

    private func pullAndOverwriteTrip(id: UUID) async throws {
        let req = TripDetailRequest(id: id, includeTrackPoints: true)
        let fresh: TripSyncPayload = try await client.post(APIEndpoint.tripDetail, body: req)
        repo.applyRemoteTrip(fresh)
    }

    private func deleteTrip(id: UUID) async throws {
        guard let entity = repo.fetchEntity(id: id) else { return }
        let req = TripDeleteRequest(id: id, conflictVersion: Int(entity.conflictVersion))
        do {
            let _: EmptyResponse = try await client.post(APIEndpoint.tripDelete, body: req)
        } catch APIError.tripNotFound {
            // Server already lost the trip (orphaned local pendingDelete). Treat
            // as success so the queue stops retrying — local hard-delete still happens below.
        }
        repo.deleteTripHard(id: id)
    }

    /// Server-side delete that preserves the local entity. The user un-published
    /// a trip (public→private) while Cloud Sync is OFF, so we want zero trace
    /// on the server (privacy-first) but the trip itself stays in their local
    /// "Мои" tab. Backend `softDelete` cascades to all photos in R2, so we
    /// don't need a separate photo-delete loop.
    private func unpublishTrip(id: UUID) async throws {
        guard let entity = repo.fetchEntity(id: id) else { return }
        // No serverCreatedAt = trip never reached the server → nothing to delete.
        guard entity.serverCreatedAt != nil else {
            repo.markUnpublished(tripId: id)
            return
        }
        // Bring home anything the device does not have a copy of, BEFORE the
        // server loses its own. Taking a trip private with Cloud Sync off
        // means «no trace on the server», and the server honours that by
        // destroying the trip and its photo blobs. For a photo whose local
        // file was already gone, that blob was the last copy in existence —
        // and the flip silently took the picture with it.
        //
        // Deliberately BEFORE the delete and deliberately allowed to throw:
        // a failed rescue leaves the operation in the queue to be retried, and
        // the trip stays on the server until the pictures are safe. The trip
        // is already private on this device by then, so nobody sees it in the
        // meantime — the only thing still pending is the erasure.
        try await rescueServerOnlyPhotos(tripId: id)
        await archiveDiscussion(tripId: id)
        let req = TripDeleteRequest(id: id, conflictVersion: Int(entity.conflictVersion))
        do {
            let _: EmptyResponse = try await client.post(APIEndpoint.tripDelete, body: req)
        } catch APIError.tripNotFound {
            // Already gone — treat as success, fall through to local cleanup.
        }
        repo.markUnpublished(tripId: id)
    }

    /// Downloads every photo of this trip that exists only on the server and
    /// writes it into local storage.
    ///
    /// The original is preferred and the thumbnail is the fallback — a smaller
    /// picture is still the picture, and losing it entirely is the outcome
    /// this exists to prevent.
    private func rescueServerOnlyPhotos(tripId: UUID) async throws {
        let ids = repo.serverOnlyPhotoIds(tripId: tripId)
        guard !ids.isEmpty else { return }
        for photoId in ids {
            let data = try await downloadPhotoData(photoId: photoId)
            guard let image = UIImage(data: data),
                  let filename = PhotoStorageService.savePhoto(image, for: tripId)
            else {
                // Undecodable or unwritable: refuse to proceed rather than
                // delete the only copy. The op retries.
                throw APIError.transport("photo rescue failed for \(photoId)")
            }
            repo.adoptRescuedPhoto(id: photoId, filename: filename)
        }
    }

    /// Copies the trip's discussion onto the device before the server loses it.
    ///
    /// Deliberately NOT allowed to block the erasure the way the photo rescue
    /// is: a photo that fails to come down is gone forever, while a thread
    /// that fails to come down is a conversation the owner can still remember
    /// having. Privacy is the promise being kept here; the archive is a
    /// courtesy on top of it, and a courtesy must not hold a promise hostage.
    private func archiveDiscussion(tripId: UUID) async {
        var collected: [TripComment] = []
        var cursor: String?
        // Bounded: ten pages is a very long thread, and an archive that walks
        // forever would stall the erasure it is supposed to precede.
        for _ in 0..<10 {
            do {
                let res: TripCommentsResponse = try await client.post(
                    APIEndpoint.socialComments,
                    body: TripCommentsRequest(tripId: tripId, limit: 50, cursor: cursor))
                collected.append(contentsOf: res.comments)
                guard let next = res.nextCursor else { break }
                cursor = next
            } catch {
                break
            }
        }
        DiscussionArchive.save(collected, for: tripId)
    }

    private func downloadPhotoData(photoId: UUID) async throws -> Data {
        do {
            return try await fetchPhotoBytes(photoId: photoId, type: .original)
        } catch {
            return try await fetchPhotoBytes(photoId: photoId, type: .thumbnail)
        }
    }

    private func fetchPhotoBytes(photoId: UUID, type: PhotoType) async throws -> Data {
        let url = try await photos.fetchPresignedURL(photoId: photoId, type: type)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.transport("photo download failed")
        }
        return data
    }

    // MARK: Vehicle

    private func uploadVehicle(id: UUID) async throws {
        guard let vehicle = SettingsManager.shared.vehicles.first(where: { $0.id == id }) else { return }
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let entity = try? ctx.fetch(req).first else { return }

        let payload = VehicleSyncPayload(
            id: vehicle.id,
            name: vehicle.name,
            avatarEmoji: vehicle.avatarEmoji,
            odometerKm: vehicle.odometerKm,
            level: vehicle.level,
            stickersJson: entity.stickersJSON,
            cityConsumption: vehicle.cityConsumption,
            highwayConsumption: vehicle.highwayConsumption,
            fuelPrice: vehicle.fuelPrice,
            conflictVersion: Int(entity.conflictVersion),
            lastModifiedAt: entity.lastModifiedAt ?? Date(),
            vehicleType: vehicle.type.rawValue,
            plate: vehicle.plate,
            plateVisible: vehicle.plateVisible,
            visibleToOthers: vehicle.visibleToOthers,
            fuelCurrency: vehicle.fuelCurrency
        )
        do {
            let res: VehicleUpsertResponse = try await client.post(APIEndpoint.vehicleUpsert, body: payload)
            entity.conflictVersion = Int32(res.conflictVersion)
            entity.syncStatus = SyncStatus.synced.rawValue
            try? ctx.save()
        } catch let err as APIError {
            if case .conflictDetected = err {
                // Next sync/pull reconciles
            } else {
                throw err
            }
        }
    }

    private func deleteVehicle(id: UUID) async throws {
        let _: EmptyResponse = try await client.post(APIEndpoint.vehicleDelete, body: VehicleDeleteRequest(id: id))
        repo.deleteVehicleHard(id: id)
    }

    // MARK: Settings

    private func uploadSettings() async throws {
        let sm = SettingsManager.shared
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<UserSettingsEntity> = UserSettingsEntity.fetchRequest()
        req.fetchLimit = 1
        guard let entity = try? ctx.fetch(req).first else { return }

        let payload = SettingsSyncPayload(
            id: sm.localUserId,
            avatarEmoji: sm.avatarEmoji,
            themeMode: entity.themeMode ?? "dark",
            language: entity.language ?? "ru",
            distanceUnit: entity.distanceUnit ?? "km",
            volumeUnit: entity.volumeUnit ?? "liters",
            fuelConsumption: entity.fuelConsumption,
            fuelPrice: entity.fuelPrice,
            fuelCurrency: entity.fuelCurrency ?? "€",
            selectedVehicleId: sm.selectedVehicleId,
            profileLevel: Int(entity.profileLevel),
            profileXp: Int(entity.profileXP),
            currentStreak: Int(entity.currentStreak),
            bestStreak: Int(entity.bestStreak),
            lastTripDate: entity.lastTripDate,
            conflictVersion: Int(entity.conflictVersion),
            lastModifiedAt: entity.lastModifiedAt ?? Date()
        )
        do {
            let res: SettingsUpsertResponse = try await client.post(APIEndpoint.settingsUpsert, body: payload)
            entity.conflictVersion = Int32(res.conflictVersion)
            entity.syncStatus = SyncStatus.synced.rawValue
            try? ctx.save()
        } catch let err as APIError {
            if case .conflictDetected = err {
                // next pull reconciles
            } else {
                throw err
            }
        }
    }

    // MARK: Photo

    private func uploadPhoto(id: UUID) async throws {
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let entity = try? ctx.fetch(req).first,
              let filename = entity.filename,
              let tripIdValue = entity.trip?.id else { return }
        // Mirror of `uploadTrip`'s privacy re-check. If the parent trip was
        // toggled back to private after this op was enqueued, don't ship the
        // photo bytes to R2.
        if !SettingsManager.shared.cloudSyncEnabled,
           let parentTrip = entity.trip, parentTrip.isPrivate {
            entity.syncStatus = SyncStatus.synced.rawValue
            try? ctx.save()
            return
        }

        guard let originalData = PhotoStorageService.photoData(filename: filename) else {
            photoLog.notice("photo \(id, privacy: .public) FAIL: missing local blob \(filename, privacy: .public)")
            entity.uploadStatus = PhotoUploadStatus.failed.rawValue
            try? ctx.save()
            return
        }

        // Decide which variants we need from entity state (read here on the view
        // context), capture the metadata, then do ALL image work off the main
        // actor. UIImage decode + UIGraphicsImageRenderer rasterize + JPEG encode
        // is among the heaviest CPU/memory work in the app and was running on
        // @MainActor for every photo as the Cloud-Sync queue drained.
        let needThumbnail = entity.thumbnailURL == nil
        // Original is uploaded on ANY connection now. It used to be gated behind
        // `isOnWiFi`, so cellular / VPN / hotspot users got thumb-only on the
        // server FOREVER — the retry path re-applied the same gate every cycle.
        // The 1440/q0.7 original is only ~50-120 KB (kept small for RU DPI), so
        // there's no bandwidth reason to defer it.
        let needOriginal = entity.remoteURL == nil
        let caption = entity.caption
        let timestamp = entity.timestamp ?? Date()
        let opStart = Date()
        photoLog.notice("photo \(id, privacy: .public) begin: origBytes=\(originalData.count, privacy: .public) needThumb=\(needThumbnail, privacy: .public) needOrig=\(needOriginal, privacy: .public) wifi=\(CacheManager.shared.isOnWiFi, privacy: .public)")

        let variants: (thumbnail: Data?, original: Data?)
        if needThumbnail || needOriginal {
            guard let decoded = await Self.encodePhotoVariants(
                originalData: originalData,
                makeThumbnail: needThumbnail,
                makeOriginal: needOriginal) else {
                // Undecodable file (corrupt) — same as the old combined guard.
                photoLog.notice("photo \(id, privacy: .public) FAIL: undecodable/corrupt image")
                entity.uploadStatus = PhotoUploadStatus.failed.rawValue
                try? ctx.save()
                return
            }
            variants = decoded
        } else {
            variants = (nil, nil)
        }

        // Thumbnail target ~5-12 KB at 200pt @ scale 1.0. `resized` defaults
        // to screen scale and was 3×-ing thumbnail size on retina devices.
        if needThumbnail {
            guard let thumbData = variants.thumbnail else {
                photoLog.notice("photo \(id, privacy: .public) FAIL: thumbnail encode produced nil")
                entity.uploadStatus = PhotoUploadStatus.failed.rawValue
                try? ctx.save()
                return
            }
            let r = try await photos.uploadPhotoPart(
                tripId: tripIdValue, photoId: id, type: .thumbnail,
                data: thumbData, caption: caption, timestamp: timestamp,
                metadataAlreadyClean: true)
            entity.thumbnailURL = r.url
            photoLog.notice("photo \(id, privacy: .public) thumb OK: \(thumbData.count, privacy: .public)B")
            // Persist the thumbnail-only state immediately so a subsequent
            // original-upload failure doesn't lose the win we just earned.
            try? ctx.save()
        }

        // Original re-encoded at 1440pt @ quality 0.7 — 1920×0.8 was producing
        // 100-300 KB blobs that consistently timed out on RU mobile networks
        // (DPI-throttled above ~150KB). 1440×0.7 lands at 50-120 KB which
        // squeezes through. The full-screen viewer doesn't need pixel-peeping
        // resolution; we're not running a photo lab.
        // Wrapped in do/catch so an original-upload failure doesn't propagate
        // and cancel the whole op — the thumbnail above is the minimum viable
        // upload (feed cards + detail grid render fine from it). The queue
        // will retry uploadPhoto until the original lands too; meanwhile the
        // user sees their photo immediately rather than "0 загружено · ждёт
        // Wi-Fi" forever.
        if needOriginal, let boundedData = variants.original {
            let useReEncoded = boundedData.count < originalData.count
            let payload = useReEncoded ? boundedData : originalData
            do {
                let r = try await photos.uploadPhotoPart(
                    tripId: tripIdValue, photoId: id, type: .original,
                    data: payload, caption: caption, timestamp: timestamp,
                    metadataAlreadyClean: useReEncoded)
                entity.remoteURL = r.url
                photoLog.notice("photo \(id, privacy: .public) orig OK: \(payload.count, privacy: .public)B reEncoded=\(useReEncoded, privacy: .public)")
            } catch {
                // Original failed (timeout/5xx). Thumbnail is on R2 so the photo
                // is viewable; remoteURL stays nil → the queue retries the
                // original next sync cycle. Previously SILENT — this line is the
                // single most valuable signal for "photos won't upload" reports.
                photoLog.notice("photo \(id, privacy: .public) orig FAIL: \(error.localizedDescription, privacy: .public) — will retry")
            }
        }

        // "Uploaded" once the thumbnail is on R2 — that's enough for the feed
        // card and detail grid. Original is a bonus that the queue keeps
        // retrying behind the scenes (since `entity.remoteURL == nil` will
        // re-enter the original branch on next uploadPhoto pass).
        entity.uploadStatus = (entity.thumbnailURL != nil)
            ? PhotoUploadStatus.uploaded.rawValue
            : PhotoUploadStatus.uploading.rawValue
        entity.lastModifiedAt = Date()
        entity.syncStatus = SyncStatus.synced.rawValue
        try? ctx.save()
        photoLog.notice("photo \(id, privacy: .public) done: status=\(entity.uploadStatus, privacy: .public) thumb=\(entity.thumbnailURL != nil, privacy: .public) orig=\(entity.remoteURL != nil, privacy: .public) in \(Int(Date().timeIntervalSince(opStart) * 1000), privacy: .public)ms")

        // Server now has the photo. Re-broadcast so the social feed re-fetches
        // — `TripRepository.addPhoto` posted the same notification at local
        // add time, but that fired BEFORE the upload completed, so the server
        // returned a stale `photoCount=0`. This second post happens after R2
        // + DB are written, so the next refresh sees the real count.
        // No `delta` key — that signals "server-confirmed, do a refresh".
        await MainActor.run {
            NotificationCenter.default.post(
                name: .tripPhotosChanged, object: nil,
                userInfo: ["tripId": tripIdValue])
        }
    }

    /// Server-side photo delete: hits `/photos/delete` which clears R2 blobs
    /// and soft-deletes the DB row. Local row was already wiped by
    /// `TripRepository.deletePhoto`. Idempotent on the server, so retries
    /// are safe.
    private func deletePhoto(id: UUID) async throws {
        struct DeleteReq: Encodable { let photoId: UUID }
        let _: EmptyResponse = try await client.post(
            APIEndpoint.photoDelete, body: DeleteReq(photoId: id))
        // Confirm delete to UI listeners (no `delta` → triggers refresh
        // instead of optimistic bump, which the local-side notification
        // already did).
        await MainActor.run {
            NotificationCenter.default.post(
                name: .tripPhotosChanged, object: nil)
        }
    }

    /// Decode + downscale + JPEG-encode the photo variants OFF the main actor.
    /// `nonisolated async` runs on the cooperative pool (SE-0338), not the
    /// caller's `@MainActor`, so the heavy Core Graphics rasterization + JPEG
    /// encode doesn't jank the UI while the Cloud-Sync queue drains photos.
    /// `scale: 1.0` is passed so `resized` never reads `UIScreen.main` (a
    /// main-actor API) off-thread.
    /// Returns `nil` when the data can't be decoded at all (corrupt file) so the
    /// caller can mark the photo failed — mirroring the old combined
    /// `guard let sourceImage = UIImage(data:)` that this refactor split apart.
    nonisolated private static func encodePhotoVariants(
        originalData: Data, makeThumbnail: Bool, makeOriginal: Bool
    ) async -> (thumbnail: Data?, original: Data?)? {
        guard let sourceImage = UIImage(data: originalData) else { return nil }
        let thumb = makeThumbnail
            ? sourceImage.resized(maxDimension: 200, scale: 1.0)?.jpegData(compressionQuality: 0.5)
            : nil
        let orig = makeOriginal
            ? sourceImage.resized(maxDimension: 1440, scale: 1.0)?.jpegData(compressionQuality: 0.7)
            : nil
        return (thumb, orig)
    }
}

private extension UIImage {
    /// Downsize the image so its longest side fits within `maxDimension`
    /// **points**. `scale` is the *render* scale — pass 1.0 to get true
    /// `maxDimension` pixels (uploads). Default `UIGraphicsImageRenderer`
    /// behavior is screen scale, which silently 3× the pixel count on
    /// retina devices and was the cause of bloated thumbnail uploads.
    func resized(maxDimension: CGFloat, scale: CGFloat = 0) -> UIImage? {
        let s = min(maxDimension / size.width, maxDimension / size.height, 1)
        let newSize = CGSize(width: size.width * s, height: size.height * s)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale > 0 ? scale : UIScreen.main.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
