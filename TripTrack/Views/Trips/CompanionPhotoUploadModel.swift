import Foundation

/// Whether the add-photo control is offered on a trip this device does not
/// own — pulled out of `TripDetailView`'s body as a pure function so it's
/// unit-testable without SwiftUI, same shape as `CompanionsCardModel
/// .decide`.
///
/// Reuses the exact roster `TripCompanionsSection`/`CompanionsStore` already
/// fetch for this trip (`/companions/list`, cached in `CompanionsStore
/// .companionsByTrip`) — no separate network call. Per that store's own
/// documentation, a non-owner's roster is already server-filtered to
/// accepted-only (pending/declined never leave the owner's device); the
/// `status == .accepted` check here is defense in depth, not trust — the
/// same posture `CompanionsCardModel.decide` takes for the identical reason.
enum CompanionPhotoUploadModel {
    /// - Parameters:
    ///   - isOwn: `TripDetailView`'s own `isOwn` — a trip in our own
    ///     CoreData database. The owner always gets the ordinary (CoreData)
    ///     add-photo control instead, so this always reads `false` for them.
    ///   - companions: `CompanionsStore.companionsByTrip[tripId] ?? []`.
    ///   - viewerAccountId: `TokenStore.shared.accountId` — `nil` when
    ///     signed out, which must never pass regardless of what a
    ///     stale/spoofed roster might contain.
    static func canAddPhoto(
        isOwn: Bool, companions: [CompanionItem], viewerAccountId: UUID?
    ) -> Bool {
        guard !isOwn, let viewerAccountId else { return false }
        return companions.contains { $0.accountId == viewerAccountId && $0.status == .accepted }
    }

    /// Review fix (Finding 2): what `TripDetailView.uploadCompanionPhotos`
    /// should keep as `remotePhotos` after the reload it fires following a
    /// successful upload. That reload is its OWN network call
    /// (`loadRemotePhotos()`) and can fail independently of the upload
    /// that just succeeded — `loadRemotePhotos()`'s own failure path sets
    /// `remotePhotos = []`, which is correct the FIRST time a trip is
    /// opened (nothing has ever loaded) but wrong here: photos that were
    /// already visible a moment ago must not vanish because a follow-up
    /// refresh blipped. Pulled out as a pure function, mirroring
    /// `canAddPhoto` above, so this rule is unit-testable without SwiftUI.
    ///
    /// - Parameters:
    ///   - previous: what `remotePhotos` held BEFORE this reload attempt.
    ///   - reloaded: what `loadRemotePhotos()` actually wrote into
    ///     `remotePhotos` — empty on failure, the fresh server list on
    ///     success.
    ///   - reloadFailed: `photosLoadFailed` as `loadRemotePhotos()` left
    ///     it.
    static func resolvedPhotosAfterReload(
        previous: [SocialTripPhoto], reloaded: [SocialTripPhoto], reloadFailed: Bool
    ) -> [SocialTripPhoto] {
        reloadFailed ? previous : reloaded
    }
}
