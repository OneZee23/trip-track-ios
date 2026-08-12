import Foundation

/// Trip companion DTOs — mirrors `companions.service.ts` /
/// `trip-companion.entity.ts` on the backend (`/companions/*`, seven
/// endpoints). `CompanionStatus` is a raw `Int` to match the server's
/// `smallint` column (`TripCompanionEntity.status`) 1:1 rather than a
/// `String` enum — there is nothing here a newer server would extend with
/// an unrecognized case the way `NotificationKind` guards against.

// MARK: - Status

enum CompanionStatus: Int, Codable {
    case pending = 0
    case accepted = 1
    case declined = 2
}

// MARK: - Roster row

/// A row in a trip's companion roster (`/companions/list`). Declined rows
/// are only ever sent to the trip owner and pending rows are hidden from
/// everyone else — a server-side filter (`CompanionsService.list`), not
/// something this DTO enforces.
struct CompanionItem: Codable, Identifiable, Hashable {
    let accountId: UUID
    let displayName: String?
    let avatarEmoji: String?
    let status: CompanionStatus

    var id: UUID { accountId }
}

// MARK: - Candidate (invite picker)

/// A followed account eligible to be invited (`/companions/candidates`).
///
/// NOTE: the server's raw query aliases the account id column as `id`, not
/// `accountId` (`CompanionsService.candidates`: `.select(['a.id AS id', ...])`)
/// — every OTHER companions row (`CompanionItem`, the `invite` result, the
/// `invite-preview` driver) sends `accountId`. `CodingKeys` bridges the wire
/// name `id` back to `accountId` so this type stays consistent with its
/// siblings on the Swift side.
struct CompanionCandidate: Codable, Identifiable, Hashable {
    let accountId: UUID
    let displayName: String?
    let avatarEmoji: String?
    let profileLevel: Int

    var id: UUID { accountId }

    enum CodingKeys: String, CodingKey {
        case accountId = "id"
        case displayName, avatarEmoji, profileLevel
    }
}

// MARK: - Invite preview

/// Driver card shown on a still-pending invite (`/companions/invite-preview`).
/// Deliberately NOT `SocialAuthor` — the server only ever sends these three
/// fields (`CompanionsService.invitePreview`: `{ accountId: driver.id,
/// displayName: driver.displayName, avatarEmoji: driver.avatarEmoji }`), no
/// `profileLevel`. Reusing `SocialAuthor` (which requires `profileLevel`)
/// would fail to decode every real invite-preview response.
struct CompanionDriverPreview: Codable, Hashable {
    let accountId: UUID
    let displayName: String?
    let avatarEmoji: String?
}

/// `/companions/invite-preview` — the ONLY thing visible before accepting:
/// no trip id, no track, no polyline, no photos, no stats. Exactly these 5
/// keys server-side (`CompanionsService.invitePreview`'s return literal).
struct CompanionInvitePreview: Codable, Hashable {
    let driver: CompanionDriverPreview?
    /// `trip.startDate`, `timestamptz` NOT NULL — always present.
    let startDate: Date
    /// meters (`trip.distance`, `double precision default 0`, NOT NULL —
    /// always present, unlike `duration` below).
    let distance: Double
    /// seconds (`trip.drivingTime`, NOT `trip.duration` — see `myTrips`'s
    /// `duration` field, which is a different, wall-clock-derived number).
    /// Sent with NO coalescing (`duration: trip.drivingTime`) and the
    /// column is `integer, nullable: true` (`trip.entity.ts`) — a trip
    /// whose driving time was never computed sends `"duration": null`.
    /// `SocialFeedTrip.drivingTime` is `Int?` for the identical column,
    /// same reasoning. MUST stay optional or every such trip's preview
    /// fails to decode entirely — the one screen a pending invitee can see
    /// before accepting.
    let duration: Double?
    /// `trip.region`, `nullable: true` — already optional, unchanged.
    let region: String?

    /// Human-readable driving time, or nil when the server never computed
    /// one (old rows predating the column, or a trip still mid-recording).
    /// Callers should OMIT the duration line entirely rather than render a
    /// misleading "0 мин"/"0 min".
    func formattedDurationHuman(_ lang: LanguageManager.Language) -> String? {
        guard let duration, duration > 0 else { return nil }
        return Trip.formattedTimeHuman(duration, lang: lang)
    }
}

// MARK: - Requests

/// Shared by `/companions/list` and `/companions/invite-preview` — both take
/// only a `tripId` (`CompanionListRequestDto` server-side, reused verbatim
/// for the preview controller method too).
struct CompanionsTripRequest: Codable {
    let tripId: UUID
}

struct CompanionsInviteRequest: Codable {
    let tripId: UUID
    let accountId: UUID
}

struct CompanionsRespondRequest: Codable {
    let tripId: UUID
    let accept: Bool
}

struct CompanionsRemoveRequest: Codable {
    let tripId: UUID
    let accountId: UUID
}

struct CompanionsCandidatesRequest: Codable {
    let tripId: UUID
    let query: String?
    let cursor: String?
}

struct CompanionsMyTripsRequest: Codable {
    let cursor: String?
}

// MARK: - Responses

struct CompanionsListResponse: Codable {
    let items: [CompanionItem]
    let isOwnerView: Bool
}

struct CompanionsCandidatesResponse: Codable {
    let items: [CompanionCandidate]
    let nextCursor: String?
}

/// `/companions/invite` wraps the created row under `companion`.
struct CompanionInviteResult: Codable, Hashable {
    let accountId: UUID
    let status: CompanionStatus
}

struct CompanionsInviteResponse: Codable {
    let companion: CompanionInviteResult
}

struct CompanionsRespondResponse: Codable {
    let status: CompanionStatus
}

struct CompanionsRemoveResponse: Codable {
    let ok: Bool
}

/// `/companions/my-trips` — items are built by the SAME `FeedItemService`
/// mapper the regular `/social/feed` uses (`CompanionsService.myTrips` calls
/// `this.feedItems.buildItems(...)`), so the wire shape of each item is
/// exactly `SocialFeedTrip`. Reusing it here (rather than a parallel type)
/// is what the brief for this task explicitly calls for.
struct CompanionsMyTripsResponse: Codable {
    let items: [SocialFeedTrip]
    let nextCursor: String?
}
