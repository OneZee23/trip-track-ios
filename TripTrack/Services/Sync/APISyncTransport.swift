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
        case (.vehicle, .upload), (.vehicle, .update):
            try await uploadVehicle(id: operation.entityId)
        case (.vehicle, .delete):
            try await deleteVehicle(id: operation.entityId)
        case (.photo, .upload), (.photo, .update):
            try await uploadPhoto(id: operation.entityId)
        case (.photo, .delete):
            break  // photos deleted via sync/push
        case (.settings, .upload), (.settings, .update):
            try await uploadSettings()
        case (.settings, .delete):
            break
        }
    }

    // MARK: Trip

    private func uploadTrip(id: UUID) async throws {
        guard let trip = repo.fetchTripDetail(id: id), let entity = repo.fetchEntity(id: id) else { return }
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

        guard let originalData = PhotoStorageService.photoData(filename: filename) else {
            entity.uploadStatus = PhotoUploadStatus.failed.rawValue
            try? ctx.save()
            return
        }

        // Thumbnail always. Target ~15-25 KB: 256pt max-dimension at 1x scale
        // (NOT screen scale — that's how thumbnails were ballooning to 1536px
        // and 160 KB on retina devices) with quality 0.6 — feed cards render
        // them at <120pt so even 256px is more than enough.
        if entity.thumbnailURL == nil {
            guard let uiImage = UIImage(data: originalData),
                  let thumb = uiImage.resized(maxDimension: 256, scale: 1.0),
                  let thumbData = thumb.jpegData(compressionQuality: 0.6) else {
                entity.uploadStatus = PhotoUploadStatus.failed.rawValue
                try? ctx.save()
                return
            }
            let r = try await photos.uploadPhotoPart(
                tripId: tripIdValue, photoId: id, type: .thumbnail,
                data: thumbData, caption: entity.caption, timestamp: entity.timestamp ?? Date())
            entity.thumbnailURL = r.url
        }

        // Original only on Wi-Fi. Re-encode capped at 1920pt (more than enough
        // for full-screen review on any iPhone) at quality 0.8 so we don't
        // upload 4-8 MB iPhone source files straight to R2 and burn the free
        // tier in a month. If the source was already small the cap is a no-op.
        if entity.remoteURL == nil && CacheManager.shared.isOnWiFi {
            guard let uiImage = UIImage(data: originalData),
                  let bounded = uiImage.resized(maxDimension: 1920, scale: 1.0),
                  let boundedData = bounded.jpegData(compressionQuality: 0.8) else {
                entity.uploadStatus = PhotoUploadStatus.failed.rawValue
                try? ctx.save()
                return
            }
            // Skip the re-encode if we'd actually make the file larger (rare
            // but possible with small sources or already-aggressive sources).
            let payload = boundedData.count < originalData.count ? boundedData : originalData
            let r = try await photos.uploadPhotoPart(
                tripId: tripIdValue, photoId: id, type: .original,
                data: payload, caption: entity.caption, timestamp: entity.timestamp ?? Date())
            entity.remoteURL = r.url
        }

        entity.uploadStatus = (entity.remoteURL != nil && entity.thumbnailURL != nil)
            ? PhotoUploadStatus.uploaded.rawValue
            : PhotoUploadStatus.uploading.rawValue
        entity.lastModifiedAt = Date()
        entity.syncStatus = SyncStatus.synced.rawValue
        try? ctx.save()
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
