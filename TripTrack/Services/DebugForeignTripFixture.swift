#if DEBUG && targetEnvironment(simulator)
import Foundation
import CoreLocation

/// Offline regression fixture for Feed → someone else's trip. No local trip
/// row, credentials or production traffic; the real navigation and detail
/// loading paths remain in use. Unavailable on physical devices and Release.
enum DebugForeignTripFixture {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-debug-foreign-trip")
    }

    /// The author's public profile, offline, for reviewing it in every state:
    /// `-debug-foreign-profile pro|free|new` (default `pro`). `pro` wears a
    /// premium background and frame; `new` is the zero-trip newcomer.
    static var profileVariant: String {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-debug-foreign-profile"), i + 1 < args.count else { return "pro" }
        return args[i + 1]
    }

    private static let authorId = "D37A2000-0000-4000-8000-000000000081"

    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ForeignTripURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static let preview: String = {
        let coordinates = (0..<3300).map { i in
            let progress = Double(i) / 3299
            return CLLocationCoordinate2D(
                latitude: 55.75 + progress * 1.2,
                longitude: 37.62 + progress * 2.1 + sin(progress * 32) * 0.025)
        }
        return Trip.encodePolyline(coordinates).base64EncodedString()
    }()

    private static func trip(refreshed: Bool) -> [String: Any] {
        [
            "id": "D37A1000-0000-4000-8000-000000000081",
            "author": [
                "id": authorId,
                "displayName": "Test Traveller", "avatarEmoji": "🚙", "profileLevel": 21,
                "isPlus": profileVariant == "pro",
                "avatarFrame": profileVariant == "pro" ? "frame_gold" : NSNull()
            ],
            "title": refreshed ? "Foreign trip updated" : "Foreign trip preview",
            "description": "Offline navigation regression fixture.",
            "startDate": "2026-09-24T09:00:00Z",
            "endDate": "2026-09-24T13:00:00Z",
            "distance": 240000, "duration": 14400,
            "maxSpeed": 28, "drivingTime": 13500, "stoppedTime": 900,
            "isPrivate": false, "previewPolyline": preview,
            "photoCount": 0, "reactionCount": 0, "reactionBreakdown": [],
            "badgeIds": [], "commentCount": 0
        ]
    }

    private static func profile() -> [String: Any] {
        let variant = profileVariant
        let isNew = variant == "new"
        let trips: [[String: Any]] = isNew ? [] : (0..<3).map { i in
            [
                "id": "D37A1000-0000-4000-8000-00000000008\(i + 2)",
                "title": ["Москва → Тверь", "По Подмосковью", "Тверь → Москва"][i],
                "startDate": "2026-09-2\(i)T09:00:00Z",
                "distance": [182_000, 64_000, 179_000][i],
                "duration": [9_600, 4_200, 9_300][i],
                "endDate": "2026-09-2\(i)T12:00:00Z",
                "region": "Moscow Oblast",
                "previewPolyline": preview,
                "isPrivate": false
            ]
        }
        return [
            "id": authorId,
            "displayName": isNew ? "Vixor66" : "Test Traveller",
            "avatarEmoji": isNew ? "🤠" : "🚙",
            "profileLevel": isNew ? 1 : 21,
            "profileBackground": variant == "free" ? NSNull() : "plus_nebula",
            "currentStreak": isNew ? 0 : 4, "bestStreak": isNew ? 0 : 12,
            "stats": [
                "totalKm": isNew ? 0 : 12_840, "tripCount": isNew ? 0 : 214,
                "regionsCount": isNew ? 0 : 9, "publicTripCount": isNew ? 0 : 37
            ],
            "activeVehicle": isNew ? NSNull() : [
                "id": "D37A3000-0000-4000-8000-000000000081", "name": "Škoda Octavia",
                "level": 7, "odometerKm": 12_840, "avatarEmoji": "🚙", "avatarStyle": NSNull()
            ],
            "recentBadges": isNew ? [] : ["marathon_42", "night_rider", "early_bird", "long_shift", "first_trip"],
            "recentTrips": trips,
            "followerCount": isNew ? 1 : 48, "followingCount": isNew ? 0 : 23,
            "isFollowing": true,
            "bio": isNew ? NSNull() : "Езжу по выходным, люблю старые дороги",
            "isPlus": variant == "pro",
            "avatarFrame": variant == "pro" ? "frame_gold" : NSNull()
        ]
    }

    private static func garageVehicle() -> [String: Any] {
        [
            "id": "D37A3000-0000-4000-8000-000000000081", "name": "Škoda Octavia",
            "avatarEmoji": "🚙", "avatarStyle": NSNull(), "vehicleType": NSNull(),
            "make": "Škoda", "model": "Octavia", "year": 2019, "bodyType": NSNull(),
            "level": 7, "odometerKm": 12_840, "about": NSNull(),
            "isArchived": false, "soldAt": NSNull(), "plate": NSNull(),
            "mapVisible": true, "photosVisible": true, "createdAt": NSNull()
        ]
    }

    private static func suggestedUser(_ i: Int, name: String, emoji: String, level: Int,
                                      reason: String, km: Double) -> [String: Any] {
        ["id": i == 0 ? authorId : "D37A4000-0000-4000-8000-00000000008\(i)",
         "displayName": name, "avatarEmoji": emoji, "profileLevel": level,
         "matchReason": reason, "totalKm": km,
         // The first suggestion is the PRO traveller of the trip fixture.
         "isPlus": i == 0, "avatarFrame": i == 0 ? "frame_gold" : NSNull()]
    }

    static func response(path: String) throws -> Data {
        let payload: [String: Any]
        if path.hasSuffix(APIEndpoint.socialFeed) {
            payload = ["trips": [trip(refreshed: false)]]
        } else if path.hasSuffix(APIEndpoint.socialTrip) {
            payload = ["item": trip(refreshed: true), "track": []]
        } else if path.hasSuffix(APIEndpoint.socialTripPhotos) {
            payload = ["photos": []]
        } else if path.hasSuffix(APIEndpoint.socialReactions) {
            payload = ["reactions": []]
        } else if path.hasSuffix(APIEndpoint.socialComments) {
            payload = ["comments": []]
        } else if path.hasSuffix("/profile"), path.contains(authorId.lowercased()) || path.contains(authorId) {
            payload = profile()
        } else if path.contains("/garage"), path.contains(authorId.lowercased()) || path.contains(authorId) {
            payload = ["vehicles": profileVariant == "new" ? [] : [garageVehicle()]]
        } else if path.contains("/journeys"), path.contains(authorId.lowercased()) || path.contains(authorId) {
            payload = ["journeys": [], "nextCursor": NSNull()]
        } else if path.hasSuffix(APIEndpoint.companionsList) {
            payload = ["items": [], "isOwnerView": false]
        } else if path.hasSuffix(APIEndpoint.socialSuggested) {
            // «Найти людей» for review: three suggestions with each rationale.
            payload = ["users": [
                suggestedUser(0, name: "Test Traveller", emoji: "🚙", level: 21, reason: "sharedRegion", km: 12_840),
                suggestedUser(1, name: "Марина К.", emoji: "🏍️", level: 9, reason: "nearby", km: 3_120),
                suggestedUser(2, name: "Alexander Konstantinopolsky", emoji: "🚐", level: 34, reason: "popular", km: 48_900),
            ]]
        } else if path.hasSuffix(APIEndpoint.socialSearch) {
            payload = ["users": [
                ["id": authorId, "displayName": "Test Traveller", "avatarEmoji": "🚙", "profileLevel": 21,
                 "isPlus": true, "avatarFrame": "frame_gold"],
            ]]
        } else {
            // Catch every other API request too: this fixture never falls
            // through to a real server, including incidental startup writes.
            return try JSONSerialization.data(withJSONObject: [
                "status": "error", "code": "FIXTURE_UNSUPPORTED",
                "message": "Endpoint is outside the offline trip fixture"
            ])
        }
        return try JSONSerialization.data(withJSONObject: ["status": "ok", "payload": payload])
    }
}

private final class ForeignTripURLProtocol: URLProtocol {
    private var work: DispatchWorkItem?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let job = DispatchWorkItem { [weak self] in
            guard let self, let url = self.request.url else { return }
            do {
                let data = try DebugForeignTripFixture.response(path: url.path)
                let response = HTTPURLResponse(url: url, statusCode: 200,
                                               httpVersion: nil,
                                               headerFields: ["Content-Type": "application/json"])!
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            } catch {
                self.client?.urlProtocol(self, didFailWithError: error)
            }
        }
        work = job
        // A separate response after presentation must update the title; a
        // frozen SwiftUI graph can otherwise look like a successful render.
        let delay = request.url?.path.hasSuffix(APIEndpoint.socialTrip) == true ? 0.5 : 0.05
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: job)
    }

    override func stopLoading() { work?.cancel() }
}
#endif
