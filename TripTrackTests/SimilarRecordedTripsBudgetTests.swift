import XCTest
import CoreLocation
@testable import TripTrack

/// Счётчик «похожих поездок» на экране итогов идёт синхронно на главном
/// актёре внутри `TripWorldEntry.rewards`. Сторож держит его цену на
/// библиотеке, которой у живых людей пока нет: 5 000 поездок с превью.
/// Перед расширением сценария (больше кандидатов, точнее совпадения) —
/// сначала сюда, потом в код.
final class SimilarRecordedTripsBudgetTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func route(offset: Double, points: Int = 60) -> [CLLocationCoordinate2D] {
        (0..<points).map { i in
            CLLocationCoordinate2D(latitude: 52.28 + offset + Double(i) * 0.002,
                                   longitude: 76.95 + offset + Double(i) * 0.0015)
        }
    }

    private func trip(_ coordinates: [CLLocationCoordinate2D], distance: Double = 15_000) -> Trip {
        Trip(startDate: date, endDate: date.addingTimeInterval(1200),
             distance: distance, maxSpeed: 25, trackPoints: [],
             previewPolyline: Trip.encodePolyline(coordinates))
    }

    func testFiveThousandTripHistoryStaysWithinBudget() {
        let current = trip(route(offset: 0))
        // Mix: a tenth share the same road (worst case — full fingerprint),
        // the rest are elsewhere and should be rejected early.
        let history = (0..<5_000).map { i in
            i % 10 == 0 ? trip(route(offset: 0)) : trip(route(offset: Double(i % 97) * 0.05))
        }
        _ = SimilarRecordedTrips.count(for: current, in: Array(history.prefix(50)))   // warm-up
        var best = Double.infinity
        for _ in 0..<3 {
            let t = Date()
            _ = SimilarRecordedTrips.count(for: current, in: history)
            best = min(best, Date().timeIntervalSince(t) * 1000)
        }
        print("SimilarRecordedTripsBudget: 5000 trips, best of 3 = \(Int(best)) ms")
        XCTAssertLessThan(best, 100)
    }
}
