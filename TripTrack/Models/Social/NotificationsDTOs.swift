import Foundation

/// In-app notification feed DTOs. Mirrors `notifications.service.ts` on
/// the backend. The kind enum is decoded as a raw `String` so an unknown
/// future kind from a newer server doesn't crash older clients — the row
/// just renders as a generic line until the user updates the app.
enum NotificationKind: String, Codable {
    case reaction
    case follow
    case comment
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
    let isRead: Bool
    let createdAt: Date
    let actor: SocialAuthor?

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
