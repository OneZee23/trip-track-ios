import XCTest
@testable import TripTrack

/// Чужой профиль: оплаченные фон и рамку решает подписка, а не значок
/// (14 окт 2026 — выключенный значок гасил их у всех).
final class PublicCosmeticsTests: XCTestCase {
    private func profile(_ extra: String) throws -> SocialProfile {
        let json = """
        {"id":"8B1C6F7A-1E1F-4A4B-9C3D-2E5F6A7B8C9D","profileLevel":3,"currentStreak":0,"bestStreak":0,
         "stats":{"tripCount":1,"totalKm":10,"regionsCount":1,"publicTripCount":1},"recentBadges":[],"recentTrips":[],
         "followerCount":0,"followingCount":0\(extra)}
        """
        return try JSONDecoder().decode(SocialProfile.self, from: Data(json.utf8))
    }

    func testHiddenBadgeKeepsPaidCosmetics() throws {
        XCTAssertTrue(try profile(#","isPlus":false,"hasPlus":true"#).showsPaidCosmetics)
    }

    func testNoSubscriptionShowsNone() throws {
        XCTAssertFalse(try profile(#","isPlus":false,"hasPlus":false"#).showsPaidCosmetics)
    }

    /// Старый сервер без `hasPlus` — решает значок, как раньше.
    func testOlderServerFallsBackToTheBadge() throws {
        XCTAssertTrue(try profile(#","isPlus":true"#).showsPaidCosmetics)
        XCTAssertFalse(try profile("").showsPaidCosmetics)
    }
}
