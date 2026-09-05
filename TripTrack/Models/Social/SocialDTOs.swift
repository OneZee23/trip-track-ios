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
    /// The silhouette, when the server knows it. Absent means «car», which is
    /// what every vehicle was before the garage grew a second axis — and is
    /// also what a build that has never heard of this style must draw.
    let avatarStyle: String?

    /// True when `avatarEmoji` is a `pixel_car_*` asset name rather than a
    /// real emoji glyph — caller must render the bundled PNG instead of
    /// drawing the asset name as text.
    var isPixelAvatar: Bool { VehicleAvatar.isAsset(avatarEmoji) }

    /// The sprite to draw, silhouette and colour resolved together.
    var avatarAssetName: String? {
        VehicleAvatar.assetName(style: avatarStyle, avatar: avatarEmoji)
    }
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
    /// Optional so an older server that hasn't shipped this field yet still
    /// decodes — absent/`nil` reads as public via `Trip(social:)`'s
    /// `social.isPrivate ?? false`, matching every trip this field's absence
    /// could ever describe: `/social/feed` and `/companions/my-trips` both
    /// only ever returned publicly-visible-to-this-viewer trips before this
    /// field existed. Added so `TripDetailView` can tell a companion's
    /// PRIVATE trip apart from a public one instead of assuming every social
    /// trip is public (Task 5 review finding — the Share button and the
    /// reactions/comments sections all key off this).
    let isPrivate: Bool?
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
        case drivingTime, stoppedTime, region, isPrivate, previewPolyline
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
            return "\(hours)\(AppStrings.hoursUnitCompact(lang)) \(minutes)\(AppStrings.minutesUnitCompact(lang))"
        }
        return "\(minutes)\(AppStrings.minutesUnitCompact(lang))"
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

/// One trip on somebody's profile.
///
/// The server builds these with the FEED's own item builder, so the payload
/// IS a feed item and the profile renders it with the feed's own card —
/// author line, metric strip, reactions, comment count. It used to be a
/// six-field summary (id, title, date, distance, region, polyline), which is
/// why a trip on a profile was a strictly poorer object than the identical
/// trip in the feed: no time, no average speed, nothing to react to.
///
/// Everything past those six is optional so a server that still sends the old
/// summary decodes cleanly — `feedTrip(fallbackAuthor:)` fills the author from
/// the profile the card is standing on and the card simply has no reactions
/// to show. Without that tolerance one undeployed backend blanks the whole
/// profile screen, not just its trips.
struct SocialProfileRecentTrip: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String?
    let startDate: Date
    /// meters
    let distance: Double
    let region: String?
    let previewPolyline: String?

    var author: SocialAuthor? = nil
    var description: String? = nil
    var endDate: Date? = nil
    /// seconds, wall clock — the feed item's own `duration`
    var duration: Int? = nil
    /// m/s
    var maxSpeed: Double? = nil
    var elevation: Double? = nil
    var maxAltitude: Double? = nil
    /// seconds spent moving
    var drivingTime: Int? = nil
    var stoppedTime: Int? = nil
    var isPrivate: Bool? = nil
    var photoCount: Int? = nil
    var firstPhotoThumbnail: String? = nil
    var vehicle: SocialFeedVehicle? = nil
    var reactionCount: Int? = nil
    var reactionBreakdown: [ReactionTally]? = nil
    var myReaction: String? = nil
    var badgeIds: [String]? = nil
    var commentCount: Int? = nil
    /// km/h, and ONLY sent by the pre-feed-shape mapper. The feed item derives
    /// average speed from distance ÷ duration instead of carrying one.
    var averageSpeed: Double? = nil

    var distanceKm: Double { distance / 1000.0 }

    /// The feed's item for this trip. `fallbackAuthor` is the profile being
    /// looked at — it only gets used against a server that predates the
    /// feed-shaped payload, where the trips carry no author of their own.
    func feedTrip(fallbackAuthor: SocialAuthor) -> SocialFeedTrip {
        SocialFeedTrip(
            id: id,
            author: author ?? fallbackAuthor,
            title: title,
            description: description,
            startDate: startDate,
            endDate: endDate,
            distance: distance,
            duration: duration ?? legacyDurationSeconds,
            maxSpeed: maxSpeed,
            elevation: elevation,
            maxAltitude: maxAltitude,
            drivingTime: drivingTime,
            stoppedTime: stoppedTime,
            region: region,
            isPrivate: isPrivate,
            previewPolyline: previewPolyline,
            photoCount: photoCount ?? 0,
            firstPhotoThumbnail: firstPhotoThumbnail,
            vehicle: vehicle,
            reactionCount: reactionCount ?? 0,
            reactionBreakdown: reactionBreakdown ?? [],
            myReaction: myReaction,
            badgeIds: badgeIds ?? [],
            commentCountRaw: commentCount
        )
    }

    /// Duration for a pre-feed-shape payload: the moving time that mapper
    /// sent, else start→end. Zero when the server sent neither — the card
    /// prints «0 мин», which is what a trip with no known duration is.
    private var legacyDurationSeconds: Int {
        if let drivingTime, drivingTime > 0 { return drivingTime }
        guard let endDate else { return 0 }
        return max(0, Int(endDate.timeIntervalSince(startDate)))
    }
}

struct SocialActiveVehicle: Codable, Hashable {
    let id: UUID
    let name: String
    let level: Int
    /// km
    let odometerKm: Double
    let avatarEmoji: String
    /// See `SocialFeedVehicle.avatarStyle`.
    let avatarStyle: String?

    /// Mirrors `Vehicle.isPixelAvatar` so the client can render the PNG instead
    /// of drawing the asset name as text.
    var isPixelAvatar: Bool { VehicleAvatar.isAsset(avatarEmoji) }

    var avatarAssetName: String? {
        VehicleAvatar.assetName(style: avatarStyle, avatar: avatarEmoji)
    }
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
    /// Free-text «о себе» line rendered under the hero pills (Figma
    /// 117:966). Optional because only server 0.6+ sends the key at all —
    /// against today's production it decodes as nil and the hero renders
    /// exactly as it did before. Blank strings are treated as absent by the
    /// view, so a user who cleared their bio doesn't leave a gap.
    let bio: String?
    /// Что владелец разрешил показывать (0.6.3).
    ///
    /// Опционально по той же причине, что и `bio`: бэкенд без этой фичи ключа
    /// не шлёт, и старый сервер обязан декодироваться, а не ронять весь экран.
    /// Отсутствие читается как «всё открыто» — см. `SocialProfileVisibility.open`.
    let visibility: SocialProfileVisibility?
}

/// Пер-блочная видимость публичного профиля (0.6.3).
///
/// Скрытый блок ИСЧЕЗАЕТ целиком — ни плашки «скрыто», ни серой заглушки.
/// Прецедент — правило про госномер: когда его не показывают, чужой видит
/// машину без чипа номера, а не пустое место с подписью.
struct SocialProfileVisibility: Codable, Hashable {
    let counters: Bool
    let stats: Bool
    let map: Bool
    let achievements: Bool

    /// Дефолт для сервера, который про видимость ещё не знает.
    static let open = SocialProfileVisibility(
        counters: true, stats: true, map: true, achievements: true)

    /// Каждое поле опционально по отдельности: сервер может научиться слать
    /// блок раньше, чем все четыре флага, и половина ответа не должна
    /// закрывать профиль молча.
    init(counters: Bool, stats: Bool, map: Bool, achievements: Bool) {
        self.counters = counters
        self.stats = stats
        self.map = map
        self.achievements = achievements
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        counters = try c.decodeIfPresent(Bool.self, forKey: .counters) ?? true
        stats = try c.decodeIfPresent(Bool.self, forKey: .stats) ?? true
        map = try c.decodeIfPresent(Bool.self, forKey: .map) ?? true
        achievements = try c.decodeIfPresent(Bool.self, forKey: .achievements) ?? true
    }
}

// MARK: - Suggested people (Discover)

/// Row of `/social/suggested`. A superset of `SocialAuthor` rather than two
/// more fields ON it: that type is shared by feed / search / followers /
/// reactions and must not grow fields the backend doesn't send there (same
/// reasoning as `BlockedUser`). Both extras are optional — they only exist
/// on server 0.6+, and a deployment without them decodes to a row that
/// renders exactly like the pre-0.6 one.
struct SocialSuggestedUser: Codable, Hashable, Identifiable {
    let id: UUID
    let displayName: String?
    let avatarEmoji: String?
    let profileLevel: Int
    /// Machine-readable "why is this person suggested" key
    /// (`sharedRegion` / `nearby` / `popular`). NEVER rendered raw — see
    /// `SuggestionMatchReason`.
    let matchReason: String?
    /// Lifetime public mileage in km (already divided by 1000 server-side,
    /// same convention as `SocialProfileStats.totalKm`).
    let totalKm: Double?

    /// The shared shape the rest of the social stack speaks in — navigation
    /// destinations and `PublicProfileView.preloaded` both take an author.
    var author: SocialAuthor {
        SocialAuthor(id: id, displayName: displayName,
                     avatarEmoji: avatarEmoji, profileLevel: profileLevel)
    }

    var reason: SuggestionMatchReason? { SuggestionMatchReason(serverValue: matchReason) }
}

struct SocialSuggestedResponse: Codable {
    let users: [SocialSuggestedUser]
}

/// Client-side localisation of the server's suggestion rationale. Not a
/// `RawRepresentable` conformance on purpose: an unrecognised key (a reason
/// a newer server invented) must resolve to nil so the row simply drops its
/// rationale line instead of printing `"sharedRegion"` at the user.
enum SuggestionMatchReason {
    case sharedRegion
    case nearby
    case popular

    /// Accepts both `sharedRegion` and `shared_region` spellings — the two
    /// sides of the wire are shipping in parallel and JSON casing on this
    /// endpoint isn't pinned down yet.
    init?(serverValue: String?) {
        guard let raw = serverValue?
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "_", with: "")
            .lowercased(), !raw.isEmpty else { return nil }
        switch raw {
        case "sharedregion", "sharedregions": self = .sharedRegion
        case "nearby": self = .nearby
        case "popular": self = .popular
        default: return nil
        }
    }

    func label(_ lang: LanguageManager.Language) -> String {
        switch self {
        case .sharedRegion: return AppStrings.suggestReasonSharedRegion(lang)
        case .nearby: return AppStrings.suggestReasonNearby(lang)
        case .popular: return AppStrings.suggestReasonPopular(lang)
        }
    }
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
    /// Пер-блочная видимость публичного профиля (0.6.3). Та же дисциплина, что
    /// у `isPublic`: `var` с nil-дефолтом, и `syncProfileToServer` их НЕ шлёт —
    /// зеркало клиента, отправленное на каждой синхронизации профиля, затёрло
    /// бы серверный флаг. Отправляет только явный тумблер.
    var countersPublic: Bool? = nil
    var statsPublic: Bool? = nil
    var mapPublic: Bool? = nil
    var achievementsPublic: Bool? = nil

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
        try c.encodeIfPresent(countersPublic, forKey: .countersPublic)
        try c.encodeIfPresent(statsPublic, forKey: .statsPublic)
        try c.encodeIfPresent(mapPublic, forKey: .mapPublic)
        try c.encodeIfPresent(achievementsPublic, forKey: .achievementsPublic)
    }

    /// ВНИМАНИЕ: этот тип кодируется ВРУЧНУЮ, потому что отсутствующее поле
    /// означает «не менять», а синтезированный энкодер слал бы `null`.
    /// Цена: новое свойство, не добавленное И сюда, И в `encode(to:)`, молча
    /// не уезжает на сервер. Запрос при этом успешен — все поля опциональны, —
    /// так что отказ не виден ни в сборке, ни в логах. См. `VisibilityWireTests`.
    private enum CodingKeys: String, CodingKey {
        case displayName, avatarEmoji, profileBackground
        case profileLevel, profileXp, currentStreak, bestStreak
        case activeVehicleId, language, showOnPublicMap, isPublic
        case countersPublic, statsPublic, mapPublic, achievementsPublic
    }
}

// MARK: - Allowed reaction emoji (matches backend whitelist)

enum ReactionEmoji {
    /// The Figma-canon palette (Components → ReactionIcon, 6 drawn icons),
    /// in the component order: Огонь, Вау, Финиш, Перевал, Кадр, Класс.
    /// The server still stores emoji strings — the emoji IS the wire key,
    /// the drawn icon is only how it renders (`ReactionIconView`).
    /// Backend `ALLOWED_EMOJI` in `react.dto.ts` must accept every key
    /// here PLUS the legacy ones below (old app builds still send them).
    /// 🔥 — awesome, 🤯 — wild, 🏁 — reached destination,
    /// 🛣️ — nice road, 🌅 — beautiful view, 👍 — like.
    static let all: [String] = ["🔥", "🤯", "🏁", "🛣️", "🌅", "👍"]

    /// Pre-6.1 palette keys already stored on prod trips. They are never
    /// offered in the picker again, but existing reactions must survive:
    /// each legacy key renders as (and merges into) its canonical
    /// replacement, so no data is lost and no duplicate-looking pills
    /// appear. ❤️ love → 👍 like, 🏎️ fast → 🏁 finish, 🗺️ places → 🛣️ road.
    static let legacyToCanonical: [String: String] = [
        "❤️": "👍", "🏎️": "🏁", "🗺️": "🛣️",
    ]

    /// Canonical display key for any stored emoji. Robust to the
    /// U+FE0F emoji-variation-selector: 🏎️/🗺️ can round-trip through
    /// the server with or without it depending on the client build.
    static func canonical(_ emoji: String) -> String {
        if let mapped = legacyToCanonical[emoji] { return mapped }
        let stripped = emoji.replacingOccurrences(of: "\u{FE0F}", with: "")
        for (legacy, canon) in legacyToCanonical
        where legacy.replacingOccurrences(of: "\u{FE0F}", with: "") == stripped {
            return canon
        }
        return emoji
    }

    /// Server breakdown → display tallies: legacy keys folded into their
    /// canonical replacement (counts summed), sorted by popularity.
    /// Ties break on the canon palette order so the pill row is stable
    /// across refreshes instead of hopping with dictionary order.
    static func mergedTallies(_ breakdown: [ReactionTally]) -> [ReactionTally] {
        let grouped = Dictionary(grouping: breakdown, by: { canonical($0.emoji) })
        return grouped
            .map { ReactionTally(emoji: $0.key, count: $0.value.reduce(0) { $0 + $1.count }) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                let li = all.firstIndex(of: $0.emoji) ?? .max
                let ri = all.firstIndex(of: $1.emoji) ?? .max
                return li < ri
            }
    }
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
        switch self {
        case .spam:
            return AppStrings.reportReasonSpam(lang)
        case .harassment:
            return AppStrings.reportReasonHarassment(lang)
        case .hate:
            return AppStrings.reportReasonHate(lang)
        case .nudity:
            return AppStrings.reportReasonNudity(lang)
        case .violence:
            return AppStrings.reportReasonViolence(lang)
        case .illegal:
            return AppStrings.reportReasonIllegal(lang)
        case .impersonation:
            return AppStrings.reportReasonImpersonation(lang)
        case .other:
            return AppStrings.reportReasonOther(lang)
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
    var parentId: UUID?
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
    /// Thread root this is a reply to; nil for a top-level comment.
    /// Threads are one level deep — the server re-points a reply-to-a-reply
    /// at the same root.
    let parentId: UUID?
    /// Display name of the person being replied to, so a reply still reads
    /// as one when its parent sits on an earlier page. Optional so older
    /// servers keep decoding.
    let replyToName: String?
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

// MARK: - One trip (public view)

/// Request body for `/social/trip` — re-reads a single trip in the feed's
/// own item shape, for a detail screen refreshing what it already shows.
struct SocialTripRequest: Codable {
    let tripId: UUID
    /// Ask for the drive as something playable, not just drawable. Off by
    /// default: a refresh that only needs the trip's own fields has no use for
    /// a few hundred track points.
    var includeTrack: Bool = false
}

/// One step of a viewable trip's drive: where, how fast, and when.
///
/// Deliberately terse on the wire — this arrives a few hundred at a time.
struct SocialTrackPoint: Codable, Hashable {
    let lat: Double
    let lon: Double
    /// m/s, the same unit the local track stores.
    let speed: Double
    let t: Date
}

struct SocialTripResponse: Codable {
    let item: SocialFeedTrip
    /// Present only when asked for, and empty for a trip whose points never
    /// reached the server (older syncs shipped the preview polyline alone).
    var track: [SocialTrackPoint]? = nil
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

extension ProfileUpdateRequest {
    /// Launch-backfill payload: the display name and NOTHING else.
    ///
    /// Every other field of `syncProfileToServer`'s payload is a mirror of THIS
    /// device, and nothing re-reads them from the server after login — the
    /// globe opt-in is seeded only from `/auth/login`, and the name lives in a
    /// `ThisDeviceOnly`, non-syncing Keychain item. Pushing the full snapshot
    /// from a second phone that has not been opened in a while would roll the
    /// account back to that phone's stale mirror. Omitted fields are dropped by
    /// `encodeIfPresent`, and the server reads absent as "leave unchanged".
    static func nameOnly(_ displayName: String) -> ProfileUpdateRequest {
        ProfileUpdateRequest(
            displayName: displayName, avatarEmoji: nil, profileBackground: nil,
            profileLevel: nil, profileXp: nil, currentStreak: nil,
            bestStreak: nil, activeVehicleId: nil, language: nil,
            showOnPublicMap: nil)
    }
}

/// Один блок публичного профиля, который владелец может выключить (0.6.3).
enum ProfileVisibilityBlock: CaseIterable, Hashable {
    case counters, stats, map, achievements
}

/// Клиентское зеркало четырёх серверных флагов.
///
/// Дефолт — «всё открыто»: колонки на сервере заведены с `TRUE`, и любой
/// другой дефолт здесь означал бы, что профиль закрывается молча у тех, чей
/// сервер про эти флаги ещё не знает.
struct ProfileVisibilityFlags: Equatable {
    var counters: Bool
    var stats: Bool
    var map: Bool
    var achievements: Bool

    static let open = ProfileVisibilityFlags(
        counters: true, stats: true, map: true, achievements: true)

    /// Явный memberwise: собственный `init?` ниже отменяет синтезированный.
    init(counters: Bool, stats: Bool, map: Bool, achievements: Bool) {
        self.counters = counters
        self.stats = stats
        self.map = map
        self.achievements = achievements
    }

    /// Флаги из ответа `/auth/me`, либо `nil`, если сервер не прислал НИ
    /// ОДНОГО ключа.
    ///
    /// Разница принципиальна. Схлопнуть отсутствие в «всё открыто» значит
    /// показать рабочие на вид тумблеры там, где сохранять их некуда: запрос
    /// уйдёт, вернётся 200, и пользователь будет думать, что спрятал карту.
    /// Это тот же fake-succeed, ради которого у «Публичного профиля» заведён
    /// гейт на успешный `/auth/me`.
    ///
    /// Частичный ответ считается поддержкой: сервер может научиться слать блок
    /// раньше, чем все четыре ключа, и половина ответа — не её отсутствие.
    init?(_ me: MeResponse) {
        let known = [me.countersPublic, me.statsPublic, me.mapPublic, me.achievementsPublic]
        guard known.contains(where: { $0 != nil }) else { return nil }
        self.init(
            counters: me.countersPublic ?? true,
            stats: me.statsPublic ?? true,
            map: me.mapPublic ?? true,
            achievements: me.achievementsPublic ?? true)
    }

    func value(_ block: ProfileVisibilityBlock) -> Bool {
        switch block {
        case .counters: return counters
        case .stats: return stats
        case .map: return map
        case .achievements: return achievements
        }
    }

    mutating func set(_ block: ProfileVisibilityBlock, _ isOn: Bool) {
        switch block {
        case .counters: counters = isOn
        case .stats: stats = isOn
        case .map: map = isOn
        case .achievements: achievements = isOn
        }
    }
}
