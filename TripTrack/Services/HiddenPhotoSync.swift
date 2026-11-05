import CoreData
import CoreLocation
import Foundation

enum HiddenPhotoSync {
    enum Decision: Equatable {
        case keep
        case removeFromServer
        case uploadAgain
    }

    static func decision(isHidden: Bool, status: PhotoUploadStatus, hasServerCopy: Bool) -> Decision {
        if isHidden {
            guard status != .hiddenByPrivacy else { return .keep }
            return hasServerCopy ? .removeFromServer : .keep
        }
        return status == .hiddenByPrivacy ? .uploadAgain : .keep
    }

    static func preservesLocalCopyDuringPull(isHiddenLocally: Bool, status: PhotoUploadStatus) -> Bool {
        isHiddenLocally || status == .localOnly || status == .hiddenByPrivacy
    }

    @MainActor
    @discardableResult
    static func reconcile(trip: Trip, entity: TripEntity, context: NSManagedObjectContext,
                          zone: Zone? = HomeSettings.load().activeZone) -> Int {
        let resolution = HiddenPartsResolver.resolve(
            points: trip.trackPoints, recordingBreaks: trip.recordingBreaks,
            startMetres: trip.hiddenParts?.startMetres ?? PrivacySettings.load().edgeMetres ?? 0,
            endMetres: trip.hiddenParts?.endMetres ?? PrivacySettings.load().edgeMetres ?? 0,
            sections: trip.hiddenParts?.sections ?? [], zone: zone)
        guard let photos = entity.photos?.array as? [TripPhotoEntity] else { return 0 }
        var changed = 0
        for photo in photos {
            guard let id = photo.id else { continue }
            let status = PhotoUploadStatus(rawValue: photo.uploadStatus) ?? .localOnly
            let hidden = HiddenPartsResolver.photoIsHidden(
                capturedAt: photo.capturedAt,
                coordinate: photo.exifLatitude.flatMap { latitude in
                    photo.exifLongitude.map {
                        CLLocationCoordinate2D(latitude: latitude.doubleValue, longitude: $0.doubleValue)
                    }
                }, resolution: resolution, points: trip.trackPoints, zone: zone)
            let hasServerCopy = photo.remoteURL != nil || photo.thumbnailURL != nil
            switch decision(isHidden: hidden, status: status, hasServerCopy: hasServerCopy) {
            case .keep:
                if hidden && status != .hiddenByPrivacy {
                    SyncQueue.shared.cancelOperations(for: id, entityType: .photo)
                    photo.uploadStatus = PhotoUploadStatus.hiddenByPrivacy.rawValue
                    changed += 1
                }
            case .removeFromServer:
                SyncQueue.shared.cancelOperations(for: id, entityType: .photo)
                SyncEnqueuer.enqueue(
                    SyncOperation(entityType: .photo, entityId: id, action: .delete),
                    hasServerCopy: true)
                photo.uploadStatus = PhotoUploadStatus.hiddenByPrivacy.rawValue
                changed += 1
            case .uploadAgain:
                photo.remoteURL = nil
                photo.thumbnailURL = nil
                photo.uploadStatus = PhotoUploadStatus.localOnly.rawValue
                SyncEnqueuer.enqueue(SyncOperation(entityType: .photo, entityId: id, action: .upload))
                changed += 1
            }
        }
        if changed > 0 { try? context.save() }
        return changed
    }
}
