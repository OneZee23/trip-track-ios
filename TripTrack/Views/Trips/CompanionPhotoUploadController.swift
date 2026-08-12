import Foundation
import UIKit

/// Owns the upload-in-progress/outcome state for `TripDetailView`'s
/// companion add-photo control, and sequences a (possibly multi-image)
/// pick through `CompanionPhotoUploadService`. Split out of the view so the
/// batch-reporting rules below are unit-testable (`CompanionPhotoUploadTests`)
/// without SwiftUI.
///
/// **How "leaves nothing behind" is guaranteed structurally, not just by
/// convention:** this type never touches `TripDetailView`'s `remotePhotos`
/// array itself — it has no reference to it. `upload(tripId:images:)`
/// returns a bare `Bool`, and `TripDetailView` reloads `remotePhotos` from
/// the server (`loadRemotePhotos()`) if and ONLY if that return is `true`.
/// So there is no code path in which a picked-but-failed image can appear
/// in the displayed list: the list is either left exactly as the last
/// successful server load reported it (nothing succeeded — nothing added),
/// or replaced wholesale by a fresh server load (something landed — the
/// truth, not an optimistic guess).
///
/// **Batch reporting — rewritten after review caught a real bug:** an
/// earlier version stopped at the FIRST failed image (`break`), silently
/// never attempting the rest of the batch, while still reporting a flat
/// "couldn't upload" even though some photos DID land. `TripPhotoPicker`
/// (shared with the owner path) allows up to 20 picks, so this was reachable
/// any time a companion selected more than one photo. `upload` now attempts
/// EVERY image regardless of earlier failures, and reports one aggregate
/// `BatchOutcome` computed from the full set of per-image results — never a
/// single leftover error from whichever image happened to fail first.
@MainActor
final class CompanionPhotoUploadController: ObservableObject {
    /// True for the whole duration of a `upload(tripId:images:)` call —
    /// the add-photo control shows a spinner and disables itself while
    /// this is true.
    @Published private(set) var isUploading = false
    /// What happened across the whole batch just attempted. `nil` before
    /// the first `upload` call. Cleared to `nil` at the START of every new
    /// `upload` call (not left showing a stale result from a previous pick
    /// while the new one is in flight).
    @Published private(set) var lastBatchOutcome: BatchOutcome?

    /// One aggregate outcome for a whole batch — computed from every
    /// image's individual `CompanionPhotoUploadService.Outcome` (or throw),
    /// never from just the first one. `succeeded` in `.partial` counts BOTH
    /// `.full` and `.degraded` images — a degraded image DID land (its
    /// thumbnail is visible on the server), so counting it as "failed"
    /// would be its own false report.
    enum BatchOutcome: Equatable {
        /// Every image landed at full quality. Nothing to say — the
        /// reload itself is the confirmation.
        case allFull
        /// Every image landed (thumbnail at minimum), but at least one
        /// only got its thumbnail, not its original. Distinct from a
        /// failure on purpose: the photo IS visible, just at reduced
        /// quality.
        case allSucceededSomeDegraded
        /// Some images landed (full or degraded), others failed outright.
        /// `succeeded` counts full+degraded; `total` is the batch size;
        /// `total - succeeded` is how many failed.
        case partial(succeeded: Int, total: Int)
        /// No image made it past its required thumbnail.
        case allFailed
    }

    private let service: CompanionPhotoUploadService

    init(service: CompanionPhotoUploadService = .shared) {
        self.service = service
    }

    /// Uploads EVERY image in `images` — no fail-fast. A companion who
    /// picked N photos is owed N attempts; skipping the rest of a batch
    /// after the first failure (the earlier, rejected version of this
    /// method) silently drops photos with no signal that they were never
    /// even tried. Returns `true` when at least one image reached the
    /// server (full or degraded), which is the ONLY signal
    /// `TripDetailView` uses to decide whether to reload `remotePhotos`.
    @discardableResult
    func upload(tripId: UUID, images: [UIImage]) async -> Bool {
        guard !images.isEmpty else { return false }
        lastBatchOutcome = nil
        isUploading = true
        defer { isUploading = false }

        var succeeded = 0
        var degraded = 0
        for image in images {
            do {
                let outcome = try await service.upload(tripId: tripId, image: image)
                succeeded += 1
                if outcome == .degraded { degraded += 1 }
            } catch {
                // Attempted and failed — NOT a `break`. The next image in
                // the batch still gets its own attempt.
            }
        }

        let total = images.count
        let failed = total - succeeded
        switch (failed, degraded) {
        case (0, 0):
            lastBatchOutcome = .allFull
        case (0, _):
            lastBatchOutcome = .allSucceededSomeDegraded
        case (_, _) where succeeded == 0:
            lastBatchOutcome = .allFailed
        default:
            lastBatchOutcome = .partial(succeeded: succeeded, total: total)
        }
        return succeeded > 0
    }
}
