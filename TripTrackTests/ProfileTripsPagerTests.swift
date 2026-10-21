import XCTest
@testable import TripTrack

/// Чужой профиль показывал десять поездок из сорока пяти (0.9.1): превью
/// профиля продолжалось ничем. Пейджер держит продолжение — когда звать,
/// с какого курсора, когда остановиться и как не задвоить карточку.
final class ProfileTripsPagerTests: XCTestCase {

    /// Карточка в форме ответа сервера — тот же JSON, что у
    /// `FeedPreviewCachePerfTests`, с номером в id и своей датой.
    private func trip(_ n: Int, _ iso: String) -> SocialFeedTrip {
        let json: [String: Any] = [
            "id": String(format: "%08d-0000-4000-8000-000000000000", n),
            "author": ["id": "88888888-8888-4888-8888-888888888888", "displayName": "A", "profileLevel": 1],
            "title": NSNull(), "description": NSNull(),
            "startDate": iso, "endDate": NSNull(),
            "distance": 1000.0, "duration": 60,
            "maxSpeed": NSNull(), "elevation": NSNull(), "maxAltitude": NSNull(),
            "drivingTime": NSNull(), "stoppedTime": NSNull(), "region": NSNull(),
            "isPrivate": false, "previewPolyline": NSNull(),
            "photoCount": 0, "firstPhotoThumbnail": NSNull(), "vehicle": NSNull(),
            "reactionCount": 0, "reactionBreakdown": [], "myReaction": NSNull(),
            "badgeIds": [], "commentCount": 0
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(SocialFeedTrip.self, from: data)
    }

    func testContinuesFromTheLastPreviewTripWithTheServersCursor() {
        var pager = ProfileTripsPager()
        let preview = (0..<10).map { trip($0, "2026-10-0\($0 % 9 + 1)T10:00:00Z") }
        pager.reset(preview: preview, publicCount: 45)

        let last = preview.last!
        XCTAssertEqual(pager.cursor, "2026-10-01T10:00:00.000Z|\(last.id.uuidString.lowercased())",
                       "курсор обязан совпасть с encodeFeedCursor сервера: ISO с миллисекундами и строчный id")
        XCTAssertTrue(pager.shouldLoad(appearedIndex: 7, loadedCount: 10))
        XCTAssertFalse(pager.shouldLoad(appearedIndex: 3, loadedCount: 10))
    }

    func testProfileWithEverythingInThePreviewNeverAsks() {
        var pager = ProfileTripsPager()
        pager.reset(preview: (0..<7).map { trip($0, "2026-10-01T10:00:00Z") }, publicCount: 7)

        XCTAssertNil(pager.cursor)
        XCTAssertFalse(pager.shouldLoad(appearedIndex: 6, loadedCount: 7))
    }

    func testAppendsNewCardsSkipsDuplicatesAndStopsAtTheEnd() {
        var pager = ProfileTripsPager()
        var cards = (0..<10).map { trip($0, "2026-10-01T10:00:00Z") }
        pager.reset(preview: cards, publicCount: 13)
        pager.begin()
        XCTAssertFalse(pager.shouldLoad(appearedIndex: 9, loadedCount: 10), "one page in flight at a time")

        let page = SocialFeedResponse(trips: [cards[9], trip(10, "2026-09-01T10:00:00Z"),
                                             trip(11, "2026-09-01T10:00:00Z"), trip(12, "2026-09-01T10:00:00Z")],
                                      nextCursor: nil)
        pager.apply(page, to: &cards)

        XCTAssertEqual(cards.count, 13, "the boundary trip must not be duplicated")
        XCTAssertFalse(pager.shouldLoad(appearedIndex: 12, loadedCount: 13), "no cursor — the list is complete")
    }

    func testARepeatedCursorEndsThePaging() {
        var pager = ProfileTripsPager()
        var cards = (0..<10).map { trip($0, "2026-10-01T10:00:00Z") }
        pager.reset(preview: cards, publicCount: 100)
        pager.apply(SocialFeedResponse(trips: [trip(20, "2026-09-01T10:00:00Z")], nextCursor: "c1"), to: &cards)
        XCTAssertEqual(pager.cursor, "c1")
        pager.apply(SocialFeedResponse(trips: [trip(21, "2026-09-01T10:00:00Z")], nextCursor: "c1"), to: &cards)
        XCTAssertNil(pager.cursor, "a server that repeats its cursor must not loop the client")
    }

    func testAFailedPageKeepsWhatIsShownAndStops() {
        var pager = ProfileTripsPager()
        let cards = (0..<10).map { trip($0, "2026-10-01T10:00:00Z") }
        pager.reset(preview: cards, publicCount: 45)
        pager.begin()
        pager.fail()
        XCTAssertFalse(pager.isLoading)
        XCTAssertFalse(pager.shouldLoad(appearedIndex: 9, loadedCount: 10))
    }
}
