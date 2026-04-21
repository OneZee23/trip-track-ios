import Foundation
import CoreLocation

// MARK: - Author (nested in feed items & profile)

struct SocialAuthor: Codable, Hashable {
    let id: UUID
    let displayName: String?
    let avatarEmoji: String?
    let profileLevel: Int
}

// MARK: - Feed

struct SocialFeedRequest: Codable {
    let limit: Int?
    let cursor: String?
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
    let startDate: Date
    let endDate: Date?
    /// meters
    let distance: Double
    /// seconds
    let duration: Int
    let region: String?
    let previewPolyline: String?
    let photoCount: Int
    let firstPhotoThumbnail: String?
    let reactionCount: Int
    let reactionBreakdown: [ReactionTally]
    let myReaction: String?
    let badgeIds: [String]

    var distanceKm: Double { distance / 1000.0 }
    var averageSpeedKmh: Double {
        guard duration > 0 else { return 0 }
        return distanceKm / (Double(duration) / 3600.0)
    }
    var formattedDuration: String {
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        return hours > 0 ? "\(hours):\(String(format: "%02d", minutes))" : "\(minutes) min"
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
    let tripCount: Int
    let regionsCount: Int
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

struct SocialProfile: Codable, Hashable {
    let id: UUID
    let displayName: String?
    let avatarEmoji: String?
    let profileLevel: Int
    let profileBackground: String?
    let stats: SocialProfileStats
    let recentTrips: [SocialProfileRecentTrip]
    let followerCount: Int
    let followingCount: Int
    let isFollowing: Bool?
}

// MARK: - Profile appearance update

struct ProfileUpdateRequest: Codable {
    let displayName: String?
    let avatarEmoji: String?
    let profileBackground: String?
}

// MARK: - Allowed reaction emoji (matches backend whitelist)

enum ReactionEmoji {
    /// Car / road themed reactions for TripTrack.
    /// 🔥 — awesome, 🏁 — reached destination, 🏎️ — fast/impressive,
    /// 🛣️ — nice road, 🗺️ — new places explored.
    static let all: [String] = ["🔥", "🏁", "🏎️", "🛣️", "🗺️"]
}

// MARK: - Block / Report

struct SocialBlockRequest: Codable {
    let targetAccountId: UUID
}

struct SocialBlockResponse: Codable {
    let blocked: Bool
}

struct SocialBlockedListResponse: Codable {
    let users: [SocialAuthor]
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
