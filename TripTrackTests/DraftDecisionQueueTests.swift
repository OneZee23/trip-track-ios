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

    /// Ревью раунда 1, пункт 5: `applyDraftDecisions` разбирает очередь по
    /// одной записи — подсмотрел, применил, убрал, — а не всю разом.
    func testPeekDoesNotRemoveAndOrderIsPreserved() {
        let q = DraftDecisionQueue(defaults: defaults)
        let first = UUID(), second = UUID()
        q.enqueue(first, .confirm)
        q.enqueue(second, .discard)
        XCTAssertEqual(q.peek()?.0, first, "голова очереди — самая старая запись")
        XCTAssertEqual(q.peek()?.0, first, "peek ничего не убирает")
        q.remove(first)
        XCTAssertEqual(q.peek()?.0, second)
        q.remove(second)
        XCTAssertNil(q.peek())
    }

    /// Убрать запись, которой нет, — не ошибка и не трогает соседей.
    func testRemoveIsANoOpForAnUnknownIdAndLeavesOthersAlone() {
        let q = DraftDecisionQueue(defaults: defaults)
        let known = UUID()
        q.enqueue(known, .confirm)
        q.remove(UUID())
        XCTAssertEqual(q.peek()?.0, known)
    }
}
