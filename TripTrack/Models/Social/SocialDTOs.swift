import Foundation
import CoreLocation

// MARK: - Author (nested in feed items & profile)

struct SocialAuthor: Codable, Hashable {
    let id: UUID
    let displayName: String?
    let avatarEmoji: String?
    let profileLevel: Int
}

/// Lightweight vehicle metadata shipped on each feed item — name + avatar
/// emoji is enough for the card's small "what car was this in?" line.
struct SocialFeedVehicle: Codable, Hashable {
    let name: String
    let avatarEmoji: String

    /// True when `avatarEmoji` is a `pixel_car_*` asset name rather than a
    /// real emoji glyph — caller must render the bundled PNG instead of
    /// drawing the asset name as text.
    var isPixelAvatar: Bool { avatarEmoji.hasPrefix("pixel_car_") }
}

// MARK: - Feed

struct SocialFeedRequest: Codable {
    let limit: Int?
    let cursor: String?
    /// Feed composition: nil/"all" = global discovery feed (default, what
    /// deployed servers understand); "following" = followed users + own
    /// public trips only (backend feat/account-page+). encodeIfPresent via
    /// optional keeps old servers happy — they ignore unknown fields.
    var type: String? = nil
}

struct SocialFeedResponse: Codable {
    let trips: [SocialFeedTrip]
    let nextCursor: String?
}

struct ReactionTally: Codable, Hashable {
    let emoji: String
    let count: Int
}

struct SocialFeedTrip: Codable, Identifiable, Hashable {
    let id: UUID
    let author: SocialAuthor
    let title: String?
    /// User-authored notes. Server-rendered for every viewer (own + others)
    /// so the social detail isn't sparse vs the owner's edit-able copy.
    let description: String?
    let startDate: Date
    let endDate: Date?
    /// meters
    let distance: Double
    /// seconds
    let duration: Int
    /// m/s — same units as the local Trip model
    let maxSpeed: Double?
    /// metres — elevation gain (sum of positive altitude deltas, computed
    /// client-side from track points before upload). Same units as local Trip.
    let elevation: Double?
    /// metres — peak altitude reached during the trip. Optional because old
    /// clients (pre-0.5.6) don't send it; old server records will be null.
    let maxAltitude: Double?
    /// seconds — wall-clock time the car was actually moving. Optional, same
    /// 0.5.6 backfill story as `maxAltitude`.
    let drivingTime: Int?
    /// seconds — wall-clock time the trip stayed stationary (red lights,
    /// gas stops, drive-thru queues). Optional, see above.
    let stoppedTime: Int?
    let region: String?
    let previewPolyline: String?
    // `var` so SocialFeedStore can apply optimistic bumps when the user adds
    // or removes a photo on their own trip — eliminates the 1-2s gap between
    // local save and server-side `/social/feed` re-render.
    var photoCount: Int
    var firstPhotoThumbnail: String?
    /// Vehicle name + avatar that the trip was recorded in. Server-rendered
    /// for every trip in the feed so own and others' cards share the same
    /// "what car was this in?" line — no more silently hiding it for non-self
    /// authors.
    let vehicle: SocialFeedVehicle?
    let reactionCount: Int
    let reactionBreakdown: [ReactionTally]
    let myReaction: String?
    let badgeIds: [String]
    /// Raw server comment total. Optional because the comments backend
    /// isn't deployed yet — old servers omit the key entirely, and the
    /// synthesized `decodeIfPresent` maps an absent key to nil instead of
    /// failing the whole feed decode. Read via `commentCount`.
    let commentCountRaw: Int?

    /// Decode-safe comment total: absent key (pre-comments backend) → 0.
    var commentCount: Int { commentCountRaw ?? 0 }

    /// Explicit keys only to map `commentCountRaw` ← "commentCount" —
    /// every other property keys as itself.
    enum CodingKeys: String, CodingKey {
        case id, author, title, description, startDate, endDate
        case distance, duration, maxSpeed, elevation, maxAltitude
        case drivingTime, stoppedTime, region, previewPolyline
        case photoCount, firstPhotoThumbnail, vehicle
        case reactionCount, reactionBreakdown, myReaction, badgeIds
        case commentCountRaw = "commentCount"
    }

    var distanceKm: Double { distance / 1000.0 }
    var maxSpeedKmh: Double { (maxSpeed ?? 0) * 3.6 }
    var averageSpeedKmh: Double {
        guard duration > 0 else { return 0 }
        return distanceKm / (Double(duration) / 3600.0)
    }
    /// Human-readable duration formatter that matches the owner-side
    /// `Trip.formattedDurationHuman(lang:)` — "1 ч 19 мин" / "1 h 19 min"
    /// instead of the previous ambiguous "1:19". Friends' trips should
    /// read like the owner's own detail screen for the same trip.
    func formattedDurationHuman(_ lang: LanguageManager.Language) -> String {
        Trip.formattedTimeHuman(TimeInterval(duration), lang: lang)
    }
    /// Compact variant for the feed-card metric strip where horizontal
    /// space per column is ~110pt and the full "1 ч 19 мин" overflows.
    /// Drops the space between number and unit ("1ч 19м") so the typical
    /// 1–3 hour trip fits without auto-shrink kicking in.
    func formattedDurationCompact(_ lang: LanguageManager.Language) -> String {
        let totalSeconds = duration
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return lang == .ru ? "\(hours)ч \(minutes)м" : "\(hours)h \(minutes)m"
        }
        return lang == .ru ? "\(minutes)м" : "\(minutes)m"
    }
    func formattedDrivingTimeHuman(_ lang: LanguageManager.Language) -> String? {
        guard let s = drivingTime, s > 0 else { return nil }
        return Trip.formattedTimeHuman(TimeInterval(s), lang: lang)
    }
    func formattedStoppedTimeHuman(_ lang: LanguageManager.Language) -> String? {
        guard let s = stoppedTime, s > 0 else { return nil }
        return Trip.formattedTimeHuman(TimeInterval(s), lang: lang)
    }
    var previewCoordinates: [CLLocationCoordinate2D] {
        guard let s = previewPolyline, let data = Data(base64Encoded: s) else { return [] }
        return Trip.decodePolyline(data)
    }
}

extension SocialProfileRecentTrip {
    var previewCoordinates: [CLLocationCoordinate2D] {
        guard let s = previewPolyline, let data = Data(base64Encoded: s) else { return [] }
        return Trip.decodePolyline(data)
    }
}

// MARK: - Follow

struct SocialFollowRequest: Codable {
    let targetAccountId: UUID
}

struct SocialFollowResponse: Codable {
    let following: Bool
}

struct SocialFollowersRequest: Codable {
    let accountId: UUID?
    let limit: Int?
    let offset: Int?
}

struct SocialFollowersResponse: Codable {
    let users: [SocialAuthor]
    let total: Int
}

// MARK: - Search / Suggest

struct SocialSearchRequest: Codable {
    let query: String
    let limit: Int?
}

struct SocialSuggestedRequest: Codable {
    let limit: Int?
}

struct SocialUsersResponse: Codable {
    let users: [SocialAuthor]
}

// MARK: - Reactions

struct SocialReactRequest: Codable {
    let tripId: UUID
    let emoji: String
}

struct SocialReactResponse: Codable {
    let reacted: Bool
}

struct SocialUnreactRequest: Codable {
    let tripId: UUID
}

// MARK: - Share

struct SocialShareRequest: Codable {
    let tripId: UUID
    let expiresInDays: Int?
}

struct SocialShareResponse: Codable {
    let shareUrl: String
    let shareCode: String
    let expiresAt: Date?
}

// MARK: - Profile

struct SocialProfileStats: Codable, Hashable {
    /// km (already divided by 1000 on backend)
    let totalKm: Double
    /// Total trip count including private trips.
    let tripCount: Int
    let regionsCount: Int
    /// How many of those trips are currently public.
    let publicTripCount: Int
}

struct SocialProfileRecentTrip: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String?
    let startDate: Date
    /// meters
    let distance: Double
    let region: String?
    let previewPolyline: String?

    var distanceKm: Double { distance / 1000.0 }
}

struct SocialActiveVehicle: Codable, Hashable {
    let id: UUID
    let name: String
    let level: Int
    /// km
    let odometerKm: Double
    let avatarEmoji: String

    /// Mirrors `Vehicle.isPixelAvatar` so the client can render the PNG instead
    /// of drawing the asset name as text.
    var isPixelAvatar: Bool { avatarEmoji.hasPrefix("pixel_car_") }
}

struct SocialProfile: Codable, Hashable {
    let id: UUID
    let displayName: String?
    let avatarEmoji: String?
    let profileLevel: Int
    let profileBackground: String?
    let currentStreak: Int
    let bestStreak: Int
    let stats: SocialProfileStats
    let activeVehicle: SocialActiveVehicle?
    let recentBadges: [String]
    let recentTrips: [SocialProfileRecentTrip]
    let followerCount: Int
    let followingCount: Int
    let isFollowing: Bool?
}

// MARK: - Profile appearance update

/// Client → server push of mutable profile fields. Nil fields are OMITTED
/// from the JSON (see `encode(to:)`) — the server treats absent keys as
/// "leave unchanged" but would treat `null` as "clear this field".
struct ProfileUpdateRequest: Encodable {
    let displayName: String?
    let avatarEmoji: String?
    let profileBackground: String?
    let profileLevel: Int?
    let profileXp: Int?
    let currentStreak: Int?
    let bestStreak: Int?
    /// UUID string of the active vehicle. Empty string clears the selection
    /// server-side; nil means "don't change".
    let activeVehicleId: String?
    /// `"ru"` or `"en"`. Server uses this to localise scheduled push texts
    /// (weekly recap and similar). nil = "don't change".
    let language: String?
    /// Opt-IN to the public website globe (account-level). nil = "don't change".
    let showOnPublicMap: Bool?
    /// Account-level profile visibility («Публичный профиль» toggle).
    /// `var` with a nil default so the memberwise init keeps every existing
    /// call site source-compatible — CRITICAL: `syncProfileToServer` must
    /// never send this field (a stale client mirror pushed on every profile
    /// sync would clobber the server flag); only the explicit
    /// `AuthService.setPublicProfile` builds a payload containing it.
    var isPublic: Bool? = nil

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encodeIfPresent(avatarEmoji, forKey: .avatarEmoji)
        try c.encodeIfPresent(profileBackground, forKey: .profileBackground)
        try c.encodeIfPresent(profileLevel, forKey: .profileLevel)
        try c.encodeIfPresent(profileXp, forKey: .profileXp)
        try c.encodeIfPresent(currentStreak, forKey: .currentStreak)
        try c.encodeIfPresent(bestStreak, forKey: .bestStreak)
        try c.encodeIfPresent(activeVehicleId, forKey: .activeVehicleId)
        try c.encodeIfPresent(language, forKey: .language)
        try c.encodeIfPresent(showOnPublicMap, forKey: .showOnPublicMap)
        try c.encodeIfPresent(isPublic, forKey: .isPublic)
    }

    private enum CodingKeys: String, CodingKey {
        case displayName, avatarEmoji, profileBackground
        case profileLevel, profileXp, currentStreak, bestStreak
        case activeVehicleId, language, showOnPublicMap, isPublic
    }
}

// MARK: - Allowed reaction emoji (matches backend whitelist)

enum ReactionEmoji {
    /// Reactions ordered for the horizontal pill row in
    /// `SocialTripDetailView` and `ReactionPickerOverlay`. Order kept
    /// stable across releases — adding a new emoji at the end avoids
    /// reshuffling the muscle memory of repeat reactors.
    /// MUST mirror `ALLOWED_EMOJI` in `react.dto.ts` on the backend
    /// (validated server-side via `@IsIn`).
    /// 🔥 — awesome, ❤️ — love, 🏁 — reached destination,
    /// 🏎️ — fast/impressive, 🛣️ — nice road, 🗺️ — new places explored,
    /// 🌅 — beautiful view, 🤯 — wild.
    static let all: [String] = ["🔥", "❤️", "🏁", "🏎️", "🛣️", "🗺️", "🌅", "🤯"]
}

// MARK: - Block / Report

struct SocialBlockRequest: Codable {
    let targetAccountId: UUID
}

struct SocialBlockResponse: Codable {
    let blocked: Bool
}

/// Row of `/social/blocked`. Superset of `SocialAuthor` (kept separate — that
/// type is shared by feed/search and must not grow fields the backend doesn't
/// send there). `blockedAt` is an ISO8601 string, parsed at display time —
/// optional so decoding survives deployed master that doesn't send it yet.
struct BlockedUser: Codable {
    let id: UUID
    let displayName: String?
    let avatarEmoji: String?
    let profileLevel: Int
    let blockedAt: String?
}

struct SocialBlockedListResponse: Codable {
    let users: [BlockedUser]
}

enum ReportReason: String, Codable, CaseIterable, Identifiable {
    case spam
    case harassment
    case hate
    case nudity
    case violence
    case illegal
    case impersonation
    case other

    var id: String { rawValue }

    func label(_ lang: LanguageManager.Language) -> String {
        switch (self, lang) {
        case (.spam, .ru): return "Спам / реклама"
        case (.spam, .en): return "Spam or advertising"
        case (.harassment, .ru): return "Домогательства / травля"
        case (.harassment, .en): return "Harassment or bullying"
        case (.hate, .ru): return "Разжигание ненависти"
        case (.hate, .en): return "Hate speech"
        case (.nudity, .ru): return "Обнажённость / сексуальный контент"
        case (.nudity, .en): return "Nudity or sexual content"
        case (.violence, .ru): return "Насилие или угрозы"
        case (.violence, .en): return "Violence or threats"
        case (.illegal, .ru): return "Незаконные действия"
        case (.illegal, .en): return "Illegal activity"
        case (.impersonation, .ru): return "Выдаёт себя за другое лицо"
        case (.impersonation, .en): return "Impersonation"
        case (.other, .ru): return "Другое"
        case (.other, .en): return "Something else"
        }
    }
}

struct SocialReportRequest: Codable {
    let targetType: String   // "user" | "trip"
    let targetId: UUID
    let reason: String
    let notes: String?
}

struct SocialReportResponse: Codable {
    let reported: Bool
}

// MARK: - Reactions breakdown

struct SocialReactionEntry: Codable, Identifiable, Hashable {
    let user: SocialAuthor
    let emoji: String
    let createdAt: Date

    var id: String { "\(user.id.uuidString)-\(emoji)" }
}

struct SocialReactionsResponse: Codable {
    let reactions: [SocialReactionEntry]
}

// MARK: - Comments

/// `POST /social/comment` — create a comment on a public trip.
/// `text` is 1..500, trimmed client-side before sending. JWT required.
struct SocialCommentCreateRequest: Codable {
    let tripId: UUID
    let text: String
}

/// Server ack for a created comment — the optimistic local row swaps its
/// temp id/date for these authoritative values.
struct SocialCommentCreateResponse: Codable {
    let id: UUID
    let createdAt: Date
}

/// `POST /social/comments` — cursor-paged comment list (newest first).
/// Guest-readable, so callers pass `requiresAuth` per sign-in state.
struct TripCommentsRequest: Codable {
    let tripId: UUID
    let limit: Int?
    let cursor: String?
}

struct TripComment: Codable, Identifiable, Hashable {
    let id: UUID
    let user: SocialAuthor
    let text: String
    let createdAt: Date
    /// Server-computed "the viewer authored this" — drives the delete
    /// affordance without the client comparing account ids.
    let isMine: Bool
}

struct TripCommentsResponse: Codable {
    let comments: [TripComment]
    let nextCursor: String?
}

/// `POST /social/comment/delete` — allowed for the comment author or the
/// trip owner.
struct SocialCommentDeleteRequest: Codable {
    let commentId: UUID
}

struct SocialCommentDeleteResponse: Codable {
    let deleted: Bool
}

// MARK: - Trip photos (public view)

/// Request body for `/social/trip/photos` — lists photos attached to a
/// public trip (or the viewer's own). Presigned R2 URLs are short-lived
/// (~1 hour), so we re-fetch every time the detail view opens.
struct SocialTripPhotosRequest: Codable {
    let tripId: UUID
}

/// Single photo entry returned by the social photos endpoint. Both URLs
/// are optional because R2 presigning can fail independently (e.g. the
/// thumbnail upload finished but the original is still in flight).
struct SocialTripPhoto: Codable, Identifiable, Hashable {
    let id: UUID
    let caption: String?
    let timestamp: Date
    let thumbnailUrl: String?
    let originalUrl: String?
}

struct SocialTripPhotosResponse: Codable {
    let photos: [SocialTripPhoto]
}
