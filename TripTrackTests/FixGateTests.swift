import XCTest
@testable import TripTrack

/// Шлюз фикса (спека §2.1): на записи отбрасывается только заведомо ложное.
/// Потолок 65 м выбрасывал фиксы, на которых висит вечерний город, и маршрут
/// 8 сентября рвался на куски; 65 м остаются правилом одометра, а не шлюза.
final class FixGateTests: XCTestCase {
    private func decide(_ acc: Double, age: Double = 0, speed: Double = 10,
                        recording: Bool = true,
                        limit: Double = FixGate.recordingAccuracyLimit) -> FixGate.Decision {
        FixGate.decide(horizontalAccuracy: acc, ageSeconds: age, speedMS: speed,
                       isRecording: recording, recordingLimit: limit)
    }

    func testRecordingAcceptsCoarseFixesUpToTwoHundredMetres() {
        XCTAssertEqual(decide(64), .accept)
        XCTAssertEqual(decide(120), .accept)
        XCTAssertEqual(decide(200), .accept)
    }

    func testRecordingRejectsBeyondTwoHundredMetres() {
        XCTAssertEqual(decide(201), .reject(.accuracy))
    }

    /// 0.8.3: в простое потолок ТОТ ЖЕ, что на записи.
    ///
    /// Сто метров держались не по решению, а потому что вопрос отложили до
    /// этой версии. Их цена — заблокированный слайдер старта во дворе и в
    /// паркинге: под плохим небом первые фиксы приходят грубее ста метров, и
    /// человек смотрит на «Ждём сигнал GPS» там, где запись уже вполне можно
    /// начать.
    func testIdleUsesTheSameCeilingAsRecording() {
        XCTAssertEqual(decide(90, recording: false), .accept)
        XCTAssertEqual(decide(150, recording: false), .accept,
                       "грубый фикс во дворе обязан разблокировать старт")
        XCTAssertEqual(decide(200, recording: false), .accept)
        XCTAssertEqual(decide(201, recording: false), .reject(.accuracy),
                       "выше двухсот метров это позиция по вышкам, а не место")
    }

    /// Инвариант, а не число: простой НЕ имеет права быть строже записи.
    ///
    /// Разойдись они — получится состояние, в котором начать запись нельзя,
    /// хотя записывать уже было бы можно. Проверка стоит здесь, чтобы
    /// следующая настройка потолка на стенде не развела их молча.
    func testIdleIsNeverStricterThanRecording() {
        XCTAssertGreaterThanOrEqual(FixGate.idleAccuracyLimit,
                                    FixGate.recordingAccuracyLimit)
    }

    /// Прочие проверки в простое остаются: телепорт и протухший фикс
    /// отбрасываются независимо от того, идёт запись или нет.
    func testIdleStillRejectsTheObviouslyFalse() {
        XCTAssertEqual(decide(-1, recording: false), .reject(.invalid))
        XCTAssertEqual(decide(10, age: 10, recording: false), .reject(.stale))
        XCTAssertEqual(decide(10, speed: 90, recording: false), .reject(.speed))
    }

    func testInvalidStaleAndImpossibleSpeedAreRejected() {
        XCTAssertEqual(decide(-1), .reject(.invalid))
        XCTAssertEqual(decide(10, age: 10), .reject(.stale))
        XCTAssertEqual(decide(10, speed: 90), .reject(.speed))
    }

    func testUnknownSpeedIsKept() {
        XCTAssertEqual(decide(10, speed: -1), .accept)
    }

    func testTheOldPipelineCanBeReplayed() {
        XCTAssertEqual(decide(70, limit: 65), .reject(.accuracy))
    }
}
