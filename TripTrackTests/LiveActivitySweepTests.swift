import XCTest
@testable import TripTrack

/// Уборка карточек Live Activity идёт ВНЕ главного потока. На холодном старте
/// демон ActivityKit отвечает секундами, и чтение списка из главного актёра
/// было зависанием на запуске (Sentry APPLE-IOS-1A: 0.9.3, iOS 27.2).
@MainActor
final class LiveActivitySweepTests: XCTestCase {
    /// Медленный демон: список отвечает через полторы секунды. Главный поток
    /// всё это время обязан принимать работу.
    func testSlowActivityKitDoesNotBlockTheMainThread() async {
        let ended = EndedIDs()
        let slow = LiveActivityManager.SweepSource(
            ids: { Thread.sleep(forTimeInterval: 1.5); return ["old-summary"] },
            end: { await ended.add($0) }
        )
        let watchdog = MainThreadWatchdog()
        watchdog.start()
        await LiveActivityManager.sweepLingering(keeping: { nil }, source: slow)
        let gap = watchdog.stop()
        XCTAssertLessThan(gap, 500, "Список карточек читался на главном потоке: \(gap) мс")
        let ids = await ended.ids
        XCTAssertEqual(ids, ["old-summary"])
    }

    /// Карточку, которую ведёт запись, уборка не трогает: её мог завести
    /// `startActivity`, пока уборка шла в фоне.
    func testSweepKeepsTheCardOfTheCurrentRecording() async {
        let ended = EndedIDs()
        let source = LiveActivityManager.SweepSource(
            ids: { ["summary", "current", "orphan"] },
            end: { await ended.add($0) }
        )
        await LiveActivityManager.sweepLingering(keeping: { "current" }, source: source)
        let ids = await ended.ids
        XCTAssertEqual(ids, ["summary", "orphan"])
    }
}

private actor EndedIDs {
    private(set) var ids: [String] = []
    func add(_ id: String) { ids.append(id) }
}
