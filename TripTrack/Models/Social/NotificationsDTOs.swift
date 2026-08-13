import Foundation

/// In-app notification feed DTOs. Mirrors `notifications.service.ts` on
/// the backend. The kind enum is decoded as a raw `String` so an unknown
/// future kind from a newer server doesn't crash older clients — the row
/// just renders as a generic line until the user updates the app.
enum NotificationKind: String, Codable {
    case reaction
    case follow
    case comment
    /// Owner invited the recipient onto a trip. Preview-only until
    /// accepted — see `CompanionInvitePreview` — so the inbox row can never
    /// show a trip title for this kind.
    case companionInvite = "companion_invite"
    /// Recipient's own trip: someone the recipient invited (or who was
    /// invited on their trip) accepted. Ordinary informational row.
    case companionAccepted = "companion_accepted"
    /// System-authored: the recipient unlocked a badge. Actor-less by
    /// nature — nobody did this TO them — so the row is drawn on the
    /// existing no-actor path and signed «TripTrack» instead of «Кто-то».
    case achievement
}

struct NotificationItem: Codable, Identifiable, Hashable {
    let id: UUID
    /// Use the raw string so unknown kinds from a newer server don't
    /// refuse to decode the whole feed page.
    let kind: String
    let tripId: UUID?
    let tripTitle: String?
    let emoji: String?
    /// Comment rows only (server 6.1+): which comment, and a short excerpt
    /// of it. Optional so older servers keep decoding.
    let commentId: UUID?
    let commentText: String?
    /// Follow rows: does the RECIPIENT already follow this actor? Server
    /// 6.1+; nil on older servers, where the button falls back to its
    /// session-local guess.
    let isFollowing: Bool?
    let isRead: Bool
    let createdAt: Date
    let actor: SocialAuthor?
    /// `achievement` rows: which badge was unlocked, as a `Badge.all` id.
    /// The TITLE is resolved client-side so it follows the in-app language
    /// switch — a server-rendered name would freeze in whatever language
    /// the account was set to when the badge fired.
    ///
    /// `var` with a default, NOT `let`: the memberwise init is called
    /// positionally from `NotificationsInboxStore.makeRead` and the tests,
    /// and a defaulted `var` keeps both compiling untouched. Optional so
    /// today's production server (which sends no such rows at all) decodes
    /// unchanged.
    var badgeId: String? = nil

    /// Strongly-typed kind for known cases. Returns nil for unknown,
    /// callers fall back to a generic display string.
    var typedKind: NotificationKind? { NotificationKind(rawValue: kind) }
}

struct NotificationsFeedRequest: Codable {
    let limit: Int?
    let cursor: String?

    init(limit: Int? = nil, cursor: String? = nil) {
        self.limit = limit
        self.cursor = cursor
    }
}

struct NotificationsFeedResponse: Codable {
    let items: [NotificationItem]
    let nextCursor: String?
}

struct NotificationsUnreadCountResponse: Codable {
    let count: Int
}

struct NotificationsMarkReadRequest: Codable {
    /// nil = mark all; non-nil = mark specific IDs.
    let ids: [UUID]?
}
