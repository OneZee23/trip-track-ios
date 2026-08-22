import XCTest
@testable import TripTrack

/// A trip card in the owner's OWN list used to print their CURRENT level, which
/// is the same number on every card. A tester put it plainly: he knows whose
/// account he is using. The level at the TIME of the trip is the version worth
/// showing, and it can be rebuilt for the whole history because XP is stamped
/// on each trip rather than only summed into the profile.
final class TripLevelHistoryTests: XCTestCase {

    private func trip(_ daysAgo: Int, xp: Int) -> Trip {
        Trip(
            startDate: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
            xpEarned: xp
        )
    }

    func testLevelsRiseWithTheHistory() throws {
        // Thresholds: L2 at 50, L3 at 150, L4 at 300.
        let oldest = trip(30, xp: 60)    // 60  -> L2
        let middle = trip(20, xp: 100)   // 160 -> L3
        let newest = trip(10, xp: 200)   // 360 -> L4
        let levels = try XCTUnwrap(TripLevelHistory.levels(for: [newest, oldest, middle]))
        XCTAssertEqual(levels[oldest.id], 2)
        XCTAssertEqual(levels[middle.id], 3)
        XCTAssertEqual(levels[newest.id], 4)
    }

    /// Order of the input must not matter — the list arrives newest-first.
    func testInputOrderDoesNotChangeTheResult() throws {
        let a = trip(30, xp: 60), b = trip(20, xp: 100), c = trip(10, xp: 200)
        let forward = try XCTUnwrap(TripLevelHistory.levels(for: [a, b, c]))
        let backward = try XCTUnwrap(TripLevelHistory.levels(for: [c, b, a]))
        XCTAssertEqual(forward, backward)
    }

    /// The level shown is the one the trip LEFT you at, not the one you started
    /// it on — the moment worth remembering is the promotion.
    func testATripThatLevelsYouUpShowsTheNewLevel() throws {
        let first = trip(2, xp: 49)   // 49 -> still L1
        let second = trip(1, xp: 1)   // 50 -> L2
        let levels = try XCTUnwrap(TripLevelHistory.levels(for: [first, second]))
        XCTAssertEqual(levels[first.id], 1)
        XCTAssertEqual(levels[second.id], 2)
    }

    /// A history with no XP at all cannot be reconstructed. Nil means «show the
    /// current level» — printing LVL 1 on every card would be a confident lie
    /// to anyone whose library predates the field or came back from a server
    /// that does not send it.
    func testAHistoryWithoutXPReturnsNil() {
        XCTAssertNil(TripLevelHistory.levels(for: [trip(3, xp: 0), trip(1, xp: 0)]))
        XCTAssertNil(TripLevelHistory.levels(for: []))
    }

    /// One stamped trip is enough to reconstruct; the unstamped ones simply add
    /// nothing, which is what they are worth.
    func testAPartiallyStampedHistoryStillReconstructs() throws {
        let old = trip(5, xp: 0)
        let new = trip(1, xp: 200)
        let levels = try XCTUnwrap(TripLevelHistory.levels(for: [old, new]))
        XCTAssertEqual(levels[old.id], 1)
        XCTAssertEqual(levels[new.id], LevelSystem.level(for: 200))
    }

    func testNegativeXPCannotPullTheLevelDown() throws {
        let a = trip(2, xp: 200)
        let b = trip(1, xp: -500)
        let levels = try XCTUnwrap(TripLevelHistory.levels(for: [a, b]))
        XCTAssertEqual(levels[a.id], levels[b.id], "a later trip must never lower the level")
    }
}
