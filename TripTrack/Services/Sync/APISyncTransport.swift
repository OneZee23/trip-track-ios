import Foundation
import UIKit
import CoreData

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
        guard let trip = repo.fetchTripDetail(id: id), let entity = repo.fetchEntity(id: id) else { return }
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
        let payload = TripSyncPayload(trip: trip, entity: entity)
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
        let req = TripDeleteRequest(id: id, conflictVersion: Int(entity.conflictVersion))
        do {
            let _: EmptyResponse = try await client.post(APIEndpoint.tripDelete, body: req)
        } catch APIError.tripNotFound {
            // Already gone — treat as success, fall through to local cleanup.
        }
        repo.markUnpublished(tripId: id)
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
            lastModifiedAt: entity.lastModifiedAt ?? Date()
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

        guard let originalData = PhotoStorageService.photoData(filename: filename),
              let sourceImage = UIImage(data: originalData) else {
            entity.uploadStatus = PhotoUploadStatus.failed.rawValue
            try? ctx.save()
            return
        }

        // Thumbnail target ~5-12 KB at 200pt @ scale 1.0. `resized` defaults
        // to screen scale and was 3×-ing thumbnail size on retina devices.
        if entity.thumbnailURL == nil {
            guard let thumb = sourceImage.resized(maxDimension: 200, scale: 1.0),
                  let thumbData = thumb.jpegData(compressionQuality: 0.5) else {
                entity.uploadStatus = PhotoUploadStatus.failed.rawValue
                try? ctx.save()
                return
            }
            let r = try await photos.uploadPhotoPart(
                tripId: tripIdValue, photoId: id, type: .thumbnail,
                data: thumbData, caption: entity.caption, timestamp: entity.timestamp ?? Date(),
                metadataAlreadyClean: true)
            entity.thumbnailURL = r.url
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
        if entity.remoteURL == nil && CacheManager.shared.isOnWiFi {
            if let bounded = sourceImage.resized(maxDimension: 1440, scale: 1.0),
               let boundedData = bounded.jpegData(compressionQuality: 0.7) {
                let useReEncoded = boundedData.count < originalData.count
                let payload = useReEncoded ? boundedData : originalData
                do {
                    let r = try await photos.uploadPhotoPart(
                        tripId: tripIdValue, photoId: id, type: .original,
                        data: payload, caption: entity.caption, timestamp: entity.timestamp ?? Date(),
                        metadataAlreadyClean: useReEncoded)
                    entity.remoteURL = r.url
                } catch {
                    // Best-effort. Thumbnail is on R2; the photo is viewable
                    // in feed and detail. Original will retry next sync cycle.
                }
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
