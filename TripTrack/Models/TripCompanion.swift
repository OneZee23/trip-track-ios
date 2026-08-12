import Foundation

/// Offline cache of the SERVER's companion roster for one of the viewer's
/// OWN trips (`/companions/list`, via `CompanionsStore.list`).
///
/// This type used to hold a locally-invented label — a name and an emoji
/// you typed in yourself, with no server involvement (`accountId` was
/// optional, a placeholder for a real-accounts feature that didn't exist
/// yet). The product owner then decided companions must be real accounts
/// only, and the client UI that let you invent one was deleted. What
/// remains of this type is repurposed, not retired: `CompanionsStore.list`
/// writes the server's answer here after every successful load ON THE
/// VIEWER'S OWN TRIP, so the companions card still has something to draw
/// the next time that same request can't reach the network
/// (`CompanionsCardModel.decide`'s `cached` parameter).
///
/// Two invariants this type's callers must keep:
///  - It is NEVER the source of truth — `/companions/list`'s live response
///    is, and a cache hit is always flagged as possibly stale (see
///    `CompanionsCardModel.Banner.stale`), never presented as confirmed.
///  - It is NEVER written for someone else's trip.
///    `TripRepository.updateCompanions` no-ops when `tripId` has no local
///    `TripEntity`, and a foreign trip never has one — see
///    `CompanionsCachePersistenceTests` for the count-based proof.
///
/// Field-for-field mirror of `CompanionItem` (`CompanionsDTOs.swift`) so
/// converting either direction (`init(item:)` / `asCompanionItem`) is
/// lossless.
struct TripCompanion: Identifiable, Codable, Hashable {
    /// The server account this row is about — every companion cached here
    /// IS a real account.
    let accountId: UUID
    var displayName: String?
    var avatarEmoji: String?
    var status: CompanionStatus

    var id: UUID { accountId }
}

extension TripCompanion {
    /// What `CompanionsStore.list(tripId:)` caches after a successful fetch.
    init(item: CompanionItem) {
        self.init(
            accountId: item.accountId, displayName: item.displayName,
            avatarEmoji: item.avatarEmoji, status: item.status)
    }

    /// The reverse — feeding a cached roster back through
    /// `CompanionsCardModel.decide`, which only knows `CompanionItem` rows.
    var asCompanionItem: CompanionItem {
        CompanionItem(accountId: accountId, displayName: displayName, avatarEmoji: avatarEmoji, status: status)
    }
}
