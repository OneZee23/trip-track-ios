import XCTest
@testable import TripTrack

/// Пачка уведомлений — одна пересборка.
///
/// Тест существует потому, что проверить это иначе можно только настоящим
/// финишем поездки: три уведомления (`.tripRecordingEnded`,
/// `.revealedLayerChanged`, `.territoryRebuilt`) приходят подряд, и каждое до
/// 0.7.0 стоило полной сборки `CGPath` всего открытого мира.
@MainActor
final class ReloadCoalescerTests: XCTestCase {

    func testThreeNotificationsInARowProduceOneReload() async {
        var runs = 0
        let coalescer = ReloadCoalescer(window: .milliseconds(40)) { runs += 1 }

        coalescer.schedule()
        coalescer.schedule()
        coalescer.schedule()
        XCTAssertEqual(runs, 0, "пересчёт не начинается на первом же уведомлении")

        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(runs, 1, "три уведомления подряд обязаны дать один пересчёт")
    }

    /// Окно считается от ПОСЛЕДНЕГО уведомления: пачка, растянутая на
    /// полсекунды, всё равно схлопывается в одно.
    func testWindowRestartsOnEveryNotification() async {
        var runs = 0
        let coalescer = ReloadCoalescer(window: .milliseconds(60)) { runs += 1 }

        for _ in 0..<5 {
            coalescer.schedule()
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(runs, 0, "окно не перезапустилось — пересчёт ушёл посреди пачки")

        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(runs, 1)
    }

    /// Вторая пачка — второй пересчёт: схлопывание не значит «один раз за
    /// жизнь».
    func testASecondBurstReloadsAgain() async {
        var runs = 0
        let coalescer = ReloadCoalescer(window: .milliseconds(40)) { runs += 1 }

        coalescer.schedule()
        try? await Task.sleep(for: .milliseconds(200))
        coalescer.schedule()
        coalescer.schedule()
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(runs, 2)
    }

    func testCancelDropsThePendingReload() async {
        var runs = 0
        let coalescer = ReloadCoalescer(window: .milliseconds(40)) { runs += 1 }

        coalescer.schedule()
        coalescer.cancel()
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(runs, 0)
    }
}
