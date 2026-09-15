import XCTest
@testable import TripTrack

/// Чанк `/sync/push` режется по байтам JSON. Сторож двух вещей: что оценка
/// веса точки НЕ занижена против настоящего кодировщика (иначе чанк снова
/// вырастет за серверный лимит, и это снова 413 → повтор → лежащий прод), и
/// что правила упаковки держат обе границы.
final class SyncChunkBudgetTests: XCTestCase {
    private func point(_ i: Int) -> TrackPointPayload {
        TrackPointPayload(
            id: UUID(), latitude: 45.035_123_456_789 + Double(i) * 1e-6,
            longitude: 38.975_987_654_321 - Double(i) * 1e-6, altitude: 40.5 + Double(i % 7),
            speed: 16.666_666_666, course: 123.456_789, horizontalAccuracy: 4.999_999,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(i)),
            isInterpolated: i % 5 == 0)
    }

    private func payload(points: Int) -> TripSyncPayload {
        TripSyncPayload(
            id: UUID(), title: String(repeating: "Краснодар → Ростов-на-Дону ", count: 3),
            description: String(repeating: "заметка ", count: 40),
            startDate: Date(timeIntervalSince1970: 1_700_000_000), endDate: Date(timeIntervalSince1970: 1_700_040_000),
            distance: 250_123.4, maxSpeed: 31.1, averageSpeed: 16.6, fuelUsed: 18.2, elevation: 320,
            maxAltitude: 410, drivingTime: 14_950, stoppedTime: 1_200, region: "Rostov Oblast",
            isPrivate: true, vehicleId: UUID(), fuelCurrency: "RUB",
            previewPolyline: Data(repeating: 0xAB, count: 1_500).base64EncodedString(),
            badgesJson: "[\"night_owl\",\"long_haul\"]", xpEarned: 120,
            conflictVersion: 3, lastModifiedAt: Date(timeIntervalSince1970: 1_700_050_000),
            serverCreatedAt: nil, trackPoints: (0..<points).map(point), photos: nil)
    }

    /// Тот же кодировщик, что у `APIClient.serializeBody`: даты через `ISODate`.
    private func encodedSize(_ p: TripSyncPayload) throws -> Int {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .custom { date, e in
            var c = e.singleValueContainer()
            try c.encode(ISODate.format(date))
        }
        return try enc.encode(p).count
    }

    /// Оценка обязана быть ВЕРХНЕЙ: на 5 000 точках настоящий JSON меньше
    /// оценки, но не больше чем на треть (иначе бюджет 16 МБ впустую пуст).
    func testEstimateIsAnUpperBoundWithinAThird() throws {
        let p = payload(points: 5_000)
        let actual = try encodedSize(p)
        let estimate = p.estimatedWireBytes
        XCTAssertGreaterThanOrEqual(estimate, actual, "оценка занижена: \(estimate) < \(actual)")
        XCTAssertLessThan(Double(estimate), Double(actual) * 1.34, "оценка слишком щедрая: \(estimate) vs \(actual)")
    }

    /// Поездка на 89 000 точек (реальный случай 14 сен 2026) больше бюджета
    /// сама по себе — и всё равно уходит одна, а не остаётся в очереди навечно.
    func testAnOversizedSingleTripStillFormsItsOwnChunk() {
        let huge = SyncChunkBudget.estimate(trackPoints: 89_000, photos: 0, checkpoints: 0, segments: 0)
        XCTAssertGreaterThan(huge, SyncChunkBudget.maxBytes)
        XCTAssertFalse(SyncChunkBudget.shouldFlush(currentTrips: 0, currentBytes: 0, nextBytes: huge),
                       "пустой чанк не отправляют — огромная поездка добавляется в него")
        XCTAssertTrue(SyncChunkBudget.shouldFlush(currentTrips: 1, currentBytes: huge, nextBytes: 1),
                      "после огромной поездки следующая начинает новый чанк")
    }

    /// Две поездки по 30 000 точек вместе не влезают в 16 МБ — вторая идёт
    /// отдельно; две по 20 000 — вместе.
    func testPackingByBytes() {
        let big = SyncChunkBudget.estimate(trackPoints: 30_000, photos: 0, checkpoints: 0, segments: 0)
        XCTAssertTrue(SyncChunkBudget.shouldFlush(currentTrips: 1, currentBytes: big, nextBytes: big))
        let mid = SyncChunkBudget.estimate(trackPoints: 20_000, photos: 5, checkpoints: 3, segments: 1)
        XCTAssertFalse(SyncChunkBudget.shouldFlush(currentTrips: 1, currentBytes: mid, nextBytes: mid))
    }

    /// Потолок по числу поездок остался: 25 коротких поездок — новый чанк
    /// даже при крошечных байтах.
    func testMaxTripsStillCapsTheChunk() {
        let tiny = SyncChunkBudget.estimate(trackPoints: 10, photos: 0, checkpoints: 0, segments: 0)
        XCTAssertFalse(SyncChunkBudget.shouldFlush(currentTrips: 24, currentBytes: tiny * 24, nextBytes: tiny))
        XCTAssertTrue(SyncChunkBudget.shouldFlush(currentTrips: 25, currentBytes: tiny * 25, nextBytes: tiny))
    }
}
