import XCTest
@testable import TripTrack

/// Отрезок ничего не хранит — время и километры резолвятся из двух отметок
/// каждый раз при показе (см. доккомент `TripSegment`).
final class TripSegmentMetricsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func checkpoint(elapsed: TimeInterval, distance: Double, name: String? = nil) -> TripCheckpoint {
        TripCheckpoint(timestamp: start.addingTimeInterval(elapsed), latitude: 45, longitude: 38,
                       distanceFromStart: distance, elapsedFromStart: elapsed, name: name)
    }

    // MARK: - TripSegmentMetrics.resolve

    func testResolveComputesDelta() {
        let a = checkpoint(elapsed: 1_000, distance: 10_000)
        let b = checkpoint(elapsed: 4_600, distance: 55_000)
        let segment = TripSegment(fromCheckpointId: a.id, toCheckpointId: b.id)
        let resolved = TripSegmentMetrics.resolve(segment, in: [a, b])
        XCTAssertEqual(resolved?.elapsed, 3_600)
        XCTAssertEqual(resolved?.metres, 45_000)
        XCTAssertEqual(resolved?.from.id, a.id)
        XCTAssertEqual(resolved?.to.id, b.id)
    }

    /// Сегмент, у которого поля `from`/`to` перепутаны относительно времени
    /// (не должно случаться после нормализации при создании, но резолв не
    /// доверяет хранёному порядку), всё равно даёт Δ ≥ 0 и `from` раньше.
    func testResolveReordersByElapsedRegardlessOfFieldOrder() {
        let earlier = checkpoint(elapsed: 1_000, distance: 10_000)
        let later = checkpoint(elapsed: 4_600, distance: 55_000)
        // Сегмент указывает from → later, to → earlier — задом наперёд.
        let segment = TripSegment(fromCheckpointId: later.id, toCheckpointId: earlier.id)
        let resolved = TripSegmentMetrics.resolve(segment, in: [earlier, later])
        XCTAssertEqual(resolved?.from.id, earlier.id)
        XCTAssertEqual(resolved?.to.id, later.id)
        XCTAssertEqual(resolved?.elapsed, 3_600)
        XCTAssertGreaterThanOrEqual(resolved?.elapsed ?? -1, 0)
    }

    func testResolveReturnsNilWhenCheckpointMissing() {
        let a = checkpoint(elapsed: 1_000, distance: 10_000)
        let segment = TripSegment(fromCheckpointId: a.id, toCheckpointId: UUID())
        XCTAssertNil(TripSegmentMetrics.resolve(segment, in: [a]))
    }

    // MARK: - TripSegmentName.text

    func testManualNameWins() {
        let a = checkpoint(elapsed: 1_000, distance: 10_000, name: "Джубга")
        let b = checkpoint(elapsed: 4_600, distance: 55_000, name: "Сочи")
        let segment = TripSegment(fromCheckpointId: a.id, toCheckpointId: b.id, name: "Серпантин")
        XCTAssertEqual(TripSegmentName.text(segment, in: [a, b], lang: .ru), "Серпантин")
    }

    func testUnnamedSegmentBuildsArrowFromCheckpointNames() {
        let a = checkpoint(elapsed: 1_000, distance: 10_000, name: "Джубга")
        let b = checkpoint(elapsed: 4_600, distance: 55_000, name: "Сочи")
        let segment = TripSegment(fromCheckpointId: a.id, toCheckpointId: b.id)
        XCTAssertEqual(TripSegmentName.text(segment, in: [a, b], lang: .ru), "Джубга → Сочи")
    }

    /// Безымянная отметка получает «Отметка N» по её номеру во времени среди
    /// ВСЕХ отметок поездки — тем же счётом, что и лента «Моменты».
    func testUnnamedCheckpointGetsDefaultNameByTimeOrder() {
        let first = checkpoint(elapsed: 500, distance: 5_000, name: "Старт у заправки")
        let second = checkpoint(elapsed: 1_000, distance: 10_000)   // без имени — «Отметка 2»
        let third = checkpoint(elapsed: 4_600, distance: 55_000, name: "Сочи")
        let segment = TripSegment(fromCheckpointId: second.id, toCheckpointId: third.id)
        XCTAssertEqual(
            TripSegmentName.text(segment, in: [first, second, third], lang: .ru),
            "Отметка 2 → Сочи")
    }
}
