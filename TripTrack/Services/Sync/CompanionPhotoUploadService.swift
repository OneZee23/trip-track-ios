import Foundation
import UIKit

/// Uploads a picture straight to R2 for a trip the caller is an ACCEPTED
/// COMPANION on, never the owner. Task 6 of the companions work.
///
/// The ordinary owner flow (`TripManager.addPhoto` → `TripRepository
/// .addPhoto` → `TripPhotoEntity` in CoreData → `SyncQueue` → `APISync
/// Transport.uploadPhoto` drains it later) cannot be reused here: a
/// companion's device has no `TripEntity` row for a trip it doesn't own —
/// and, per this task's whole point, must never get one — so there is
/// nothing local for a batched sync op to point at. This type instead does
/// the two things the owner flow eventually does over the wire — POST a
/// thumbnail part, then an original part, to `/photos/upload` — immediately
/// and directly, with zero CoreData involved anywhere in the call chain (no
/// `import CoreData`, no `TripRepository`, no `PersistenceController`
/// reference in this file at all — structurally, not just by convention).
///
/// Reuses `R2PhotoStorage.uploadPhotoPart` UNCHANGED — the exact function
/// `APISyncTransport.uploadPhoto` (the owner path) already calls for both
/// its thumbnail and original parts — so the multipart fields
/// (`tripId`, `photoId`, `type`, `timestamp`, optional `caption`, the
/// `file` part named `"file"`) are guaranteed byte-identical to what the
/// server already accepts from the owner path; there is no second
/// field-construction call site to drift out of sync.
///
/// **BOTH variants are sent, thumbnail first — an earlier version of this
/// file sent only `original` and was WRONG; rejected by review.** The
/// reasoning at the time was that a companion has no retry queue and no
/// local record of `photoId`, so a "thumbnail landed, original failed"
/// split would leave a permanent, unretryable phantom. That reasoning
/// missed the actual server contract: `SocialService.getTripPhotos`
/// (backend, `social.service.ts`) filters its query with
/// `.andWhere('p.thumbnail_url IS NOT NULL')` — a row with only an
/// original is invisible to EVERY reader, forever, because
/// `/social/trip/photos` is the only way a companion's photo is ever read
/// back (the companion has no local copy, and the owner's `/sync/pull`
/// excludes foreign-trip photos by design). Original-only didn't avoid a
/// phantom; it manufactured a guaranteed one, on every single upload.
///
/// The two failure modes are NOT symmetric, and `upload`'s `Outcome`
/// return reflects that:
///  - **Thumbnail fails** → `upload` throws. Nothing is visible either way
///    (the server's filter guarantees it), so there is nothing to leave
///    behind; the original is never even attempted.
///  - **Thumbnail lands, original fails** → `upload` returns `.degraded`,
///    NOT a throw. The row IS returned by `/social/trip/photos` (its
///    `thumbnail_url` is set) and renders — `RemoteThumbnailView` already
///    falls back to `originalUrl` when that's nil elsewhere; here it's the
///    mirror image, rendering from `thumbnailUrl` while `originalUrl` stays
///    nil. Degraded quality, not a failure — the caller must not tell the
///    user the upload failed when their photo is actually on the trip.
@MainActor
final class CompanionPhotoUploadService {
    static let shared = CompanionPhotoUploadService()

    private let photos: R2PhotoStorage

    init(photos: R2PhotoStorage = .shared) {
        self.photos = photos
    }

    enum UploadError: Error, Equatable {
        /// The picked image couldn't be re-encoded (corrupt/unsupported data).
        case encoding
    }

    /// What happened to a single image once its thumbnail (required) landed.
    enum Outcome: Equatable {
        /// Both thumbnail and original made it to the server.
        case full
        /// Thumbnail made it (so the photo IS visible); the original did
        /// not. Not a failure — see this type's doc comment.
        case degraded
    }

    /// Long edge + JPEG quality for each variant. Mirrors
    /// `APISyncTransport.swift`'s `encodePhotoVariants` constants exactly
    /// (`resized(maxDimension: 200/1440, scale: 1.0)`,
    /// `jpegData(compressionQuality: 0.5/0.7)`) so a companion's photo
    /// looks the same as an owner's once it lands on the server.
    /// Deliberately duplicated rather than extracted into a shared helper:
    /// that file is the owner path's, covered by its own tests, and this
    /// task's own instructions are to leave it untouched rather than risk
    /// it for a refactor. The duplication is this one small, self-contained
    /// resize routine — not the multipart plumbing, which IS shared (see
    /// this type's doc comment).
    private static let thumbnailMaxDimension: CGFloat = 200
    private static let thumbnailQuality: CGFloat = 0.5
    private static let originalMaxDimension: CGFloat = 1440
    private static let originalQuality: CGFloat = 0.7

    /// Uploads one image for `tripId`, a trip this device does not own.
    /// Thumbnail first (required — see doc comment), then original
    /// (best-effort). Throws only when the thumbnail itself fails to
    /// encode or upload; a failed original after a successful thumbnail is
    /// reported via the return value, not a throw.
    @discardableResult
    func upload(tripId: UUID, image: UIImage, caption: String? = nil) async throws -> Outcome {
        guard let variants = await Self.encode(image: image) else {
            throw UploadError.encoding
        }
        // Same photoId + timestamp for both parts — they're two halves of
        // ONE photo row server-side, exactly like `APISyncTransport
        // .uploadPhoto`'s pair of calls for an existing `TripPhotoEntity`.
        let photoId = UUID()
        let timestamp = Date()

        // `UIGraphicsImageRenderer`-drawn JPEGs carry no EXIF/GPS to begin
        // with (same reasoning `APISyncTransport.uploadPhoto` documents at
        // its own re-encoded-original call site) — `metadataAlreadyClean:
        // true` skips a pointless re-decode/strip pass in `uploadPhotoPart`.
        //
        // REQUIRED: if this throws, propagate immediately. Nothing is
        // visible without a thumbnail regardless of the original, so there
        // is no reason to attempt it, and nothing has been left behind.
        _ = try await photos.uploadPhotoPart(
            tripId: tripId, photoId: photoId, type: .thumbnail,
            data: variants.thumbnail, caption: caption, timestamp: timestamp,
            metadataAlreadyClean: true
        )

        // BEST-EFFORT: a failure here does not roll back or hide the
        // thumbnail that already landed.
        do {
            _ = try await photos.uploadPhotoPart(
                tripId: tripId, photoId: photoId, type: .original,
                data: variants.original, caption: caption, timestamp: timestamp,
                metadataAlreadyClean: true
            )
            return .full
        } catch {
            return .degraded
        }
    }

    private struct EncodedVariants {
        let thumbnail: Data
        let original: Data
    }

    /// Decode + downscale + JPEG-encode BOTH variants OFF the main actor —
    /// `nonisolated async` runs on the cooperative thread pool (SE-0338),
    /// not this class's `@MainActor`, so the Core Graphics rasterize +
    /// encode work doesn't block the UI while a companion picks a photo.
    /// Mirrors `APISyncTransport.encodePhotoVariants`'s shape for the same
    /// reason. `nil` only when the source image itself can't be resized at
    /// all (near-zero dimensions) — real picked photos always succeed.
    nonisolated private static func encode(image: UIImage) async -> EncodedVariants? {
        guard let thumb = resized(image, maxDimension: thumbnailMaxDimension)?
            .jpegData(compressionQuality: thumbnailQuality),
            let orig = resized(image, maxDimension: originalMaxDimension)?
                .jpegData(compressionQuality: originalQuality)
        else { return nil }
        return EncodedVariants(thumbnail: thumb, original: orig)
    }

    nonisolated private static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
