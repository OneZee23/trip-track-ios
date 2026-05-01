import XCTest
@testable import TripTrack

final class TimeWindowDebouncerTests: XCTestCase {

    func testFirstEventPasses() {
        var d = TimeWindowDebouncer<String>(window: 5)
        XCTAssertTrue(d.shouldProcess("connect:CarAudio"))
    }

    func testSameKeyInsideWindowBlocked() {
        var d = TimeWindowDebouncer<String>(window: 5)
        let t0 = Date()
        XCTAssertTrue(d.shouldProcess("connect:CarAudio", now: t0))
        XCTAssertFalse(d.shouldProcess("connect:CarAudio", now: t0.addingTimeInterval(4.9)))
    }

    func testSameKeyAtOrAfterWindowPasses() {
        var d = TimeWindowDebouncer<String>(window: 5)
        let t0 = Date()
        d.shouldProcess("connect:CarAudio", now: t0)
        XCTAssertTrue(d.shouldProcess("connect:CarAudio", now: t0.addingTimeInterval(5.1)))
    }

    func testDifferentKeysAreIndependent() {
        var d = TimeWindowDebouncer<String>(window: 60)
        let t0 = Date()
        XCTAssertTrue(d.shouldProcess("connect:A", now: t0))
        XCTAssertTrue(d.shouldProcess("connect:B", now: t0))
        XCTAssertTrue(d.shouldProcess("disconnect:A", now: t0))
    }

    func testBlockedCallDoesNotAdvanceTimestamp() {
        var d = TimeWindowDebouncer<String>(window: 5)
        let t0 = Date()
        d.shouldProcess("k", now: t0)
        // Suppressed call at t0+3 must NOT push the window forward — otherwise
        // a noisy source firing every 3s would be permanently blocked.
        d.shouldProcess("k", now: t0.addingTimeInterval(3))
        XCTAssertTrue(d.shouldProcess("k", now: t0.addingTimeInterval(5.1)))
    }

    func testStructValueWithStruct() {
        struct EventKey: Hashable {
            let type: String
            let name: String
        }
        var d = TimeWindowDebouncer<EventKey>(window: 5)
        let t0 = Date()
        XCTAssertTrue(d.shouldProcess(EventKey(type: "connect", name: "Tesla"), now: t0))
        XCTAssertFalse(d.shouldProcess(EventKey(type: "connect", name: "Tesla"), now: t0.addingTimeInterval(2)))
        XCTAssertTrue(d.shouldProcess(EventKey(type: "disconnect", name: "Tesla"), now: t0))
    }

    func testResetClearsAllKeys() {
        var d = TimeWindowDebouncer<String>(window: 60)
        let t0 = Date()
        d.shouldProcess("a", now: t0)
        d.shouldProcess("b", now: t0)
        d.reset()
        XCTAssertTrue(d.shouldProcess("a", now: t0.addingTimeInterval(1)))
        XCTAssertTrue(d.shouldProcess("b", now: t0.addingTimeInterval(1)))
    }
}
