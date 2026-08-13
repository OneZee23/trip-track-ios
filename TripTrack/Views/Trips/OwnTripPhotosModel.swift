import Foundation

/// Fix 1 (companions review) — the trip owner's photo strip has to be the
/// UNION of the local CoreData row (offline shots, or ones not yet synced)
/// and the server roster (`/social/trip/photos`), de-duped by photo id.
///
/// Before this fix, a companion's uploaded photo had NO local row on the
/// owner's device — by design: `/sync/pull` deliberately excludes photos on
/// trips the account doesn't own (see `docs/superpowers/specs/
/// 2026-08-10-trip-companions-design.md` §1.3), and a foreign trip must
/// never gain a local CoreData row. `TripDetailView.ownPhotosSection` only
/// ever read `trip.photos`, so the whole point of the feature — someone
/// else adding photos to YOUR trip — stayed invisible to the owner. Pulled
/// out as a pure function (mirrors `CompanionPhotoUploadModel
/// .resolvedPhotosAfterReload`) so the de-dup rule is unit-testable without
/// spinning up SwiftUI.
enum OwnTripPhotosModel {
    /// Where one merged item's picture actually lives.
    enum Source: Equatable {
        case local(filename: String)
        case remote(thumbnailURL: String?, originalURL: String?)
        /// A row with nothing behind it: no file on this device and no copy
        /// on the server either. See `merge`.
        case missing(filename: String)
    }

    struct Item: Identifiable, Equatable {
        let id: UUID
        let timestamp: Date
        let source: Source
    }

    /// `local` rows come first (preserves the strip's existing order for
    /// anything already on screen today), then any REMOTE row whose id
    /// isn't already covered by a local one. `TripPhoto.id` and the
    /// server's `TripPhotoEntity.id` are the SAME uuid for a photo this
    /// device itself uploaded (`APISyncTransport.uploadPhoto` posts
    /// `photoId: id` — the local id, unchanged), so a photo that started
    /// local and finished syncing collapses onto its single local entry
    /// instead of appearing twice; a companion's photo — which never has a
    /// local entry at all — only ever contributes the remote copy.
    ///
    /// `localFileExists` is why a local row no longer wins unconditionally.
    /// A CoreData row can name a file this device does not have — the sync
    /// pull writes photo rows without ever downloading the JPEG, and a
    /// restore from backup brings the store back while `TripPhotos/` (marked
    /// `isExcludedFromBackup`) stays behind. Preferring that row meant the
    /// strip drew a dead tile even when the picture was sitting on the
    /// server under the same id, one presigned URL away. So: file present →
    /// `.local`; file gone but the server has it → `.remote`; file gone and
    /// the server does not have it → `.missing`, which the strip labels as
    /// such instead of pretending it is loading. The default keeps the
    /// function honest for callers that have no file system to ask.
    static func merge(
        local: [TripPhoto],
        remote: [SocialTripPhoto],
        localFileExists: (String) -> Bool = { _ in true }
    ) -> [Item] {
        var seen = Set<UUID>()
        var result: [Item] = []
        let remoteById = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for photo in local {
            guard seen.insert(photo.id).inserted else { continue }
            let source: Source
            if localFileExists(photo.filename) {
                source = .local(filename: photo.filename)
            } else if let twin = remoteById[photo.id],
                      twin.thumbnailUrl != nil || twin.originalUrl != nil {
                source = .remote(thumbnailURL: twin.thumbnailUrl, originalURL: twin.originalUrl)
            } else {
                source = .missing(filename: photo.filename)
            }
            result.append(Item(id: photo.id, timestamp: photo.timestamp, source: source))
        }
        for photo in remote {
            guard seen.insert(photo.id).inserted else { continue }
            result.append(Item(
                id: photo.id, timestamp: photo.timestamp,
                source: .remote(thumbnailURL: photo.thumbnailUrl, originalURL: photo.originalUrl)))
        }
        return result
    }
}
