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
    static func merge(local: [TripPhoto], remote: [SocialTripPhoto]) -> [Item] {
        var seen = Set<UUID>()
        var result: [Item] = []
        for photo in local {
            guard seen.insert(photo.id).inserted else { continue }
            result.append(Item(id: photo.id, timestamp: photo.timestamp, source: .local(filename: photo.filename)))
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
