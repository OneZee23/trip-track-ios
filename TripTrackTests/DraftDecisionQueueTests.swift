import XCTest
@testable import TripTrack

/// Review Focus 3: «Моя» из уведомления, пока приложения нет в памяти, не
/// теряется — решение ложится в очередь, переживающую перезапуск.
final class DraftDecisionQueueTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "DraftDecisionQueueTests")
        defaults.removePersistentDomain(forName: "DraftDecisionQueueTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "DraftDecisionQueueTests")
        defaults = nil
        super.tearDown()
    }

    func testDecisionSurvivesANewQueueAndDrainsOnce() {
        let id = UUID()
        DraftDecisionQueue(defaults: defaults).enqueue(id, .confirm)
        let reopened = DraftDecisionQueue(defaults: defaults)
        let first = reopened.drain()
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.0, id)
        XCTAssertEqual(first.first?.1, .confirm)
        XCTAssertTrue(reopened.drain().isEmpty)
    }

    func testTheLastDecisionForATripWins() {
        let q = DraftDecisionQueue(defaults: defaults)
        let id = UUID()
        q.enqueue(id, .confirm)
        q.enqueue(id, .discard)
        XCTAssertEqual(q.drain().map(\.1), [.discard])
    }
}
