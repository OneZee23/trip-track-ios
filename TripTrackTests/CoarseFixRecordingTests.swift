import XCTest
import CoreData
import CoreLocation
@testable import TripTrack

/// Грубые фиксы (65–200 м) пишут форму трека и не двигают одометр (спека §2.2).
@MainActor
final class CoarseFixRecordingTests: XCTestCase {
    private struct Recorded {
        let samples: [(seconds: Double, accuracy: Double)]
        let distance: Double
        let maxSpeed: Double
    }

    /// Прогон фиксов через свежую запись; читается всё ДО того, как
    /// контроллер уйдёт из памяти.
    private func record(_ fixes: [CLLocation]) -> Recorded {
        let pc = PersistenceController(inMemory: true)
        let manager = TripManager(locationManager: LocationManager(), persistenceController: pc)
        manager.startTrip(vehicleId: nil)
        fixes.forEach(manager.handleNewLocation)
        let ctx = pc.container.viewContext
        let pointRequest: NSFetchRequest<TrackPointEntity> = TrackPointEntity.fetchRequest()
        let tripRequest: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        let points = ((try? ctx.fetch(pointRequest)) ?? [])
            .sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
        let trip = (try? ctx.fetch(tripRequest))?.first
        return Recorded(
            samples: points.map { (($0.timestamp ?? .distantPast).timeIntervalSince(TrackTestKit.epoch),
                                   $0.horizontalAccuracy) },
            distance: trip?.distance ?? 0,
            maxSpeed: trip?.maxSpeed ?? 0)
    }

    /// Прямая на 10 м/с; в окне — фиксы по 120 м.
    private func drive(coarseWindow: ClosedRange<Int>?) -> [CLLocation] {
        (0...180).map { t in
            let coarse = coarseWindow?.contains(t) ?? false
            return TrackTestKit.fix(east: 0, north: Double(t) * 10, speed: 10,
                                    after: Double(t), accuracy: coarse ? 120 : 8)
        }
    }

    func testCoarseFixesDrawTheShapeButNotTheOdometer() {
        let coarse = record(drive(coarseWindow: 60...120))
        let inWindow = coarse.samples.filter { $0.seconds > 60 && $0.seconds < 120 }
        XCTAssertFalse(inWindow.isEmpty, "в окне плохого GPS трек не должен рваться")
        XCTAssertTrue(inWindow.allSatisfy { $0.accuracy == 120 },
                      "в точке лежит сырая точность GPS, а не оценка фильтра")

        let clean = record(drive(coarseWindow: nil))
        XCTAssertEqual(coarse.distance, clean.distance, accuracy: clean.distance * 0.01,
                       "через окно одометр мостится прямой, как и раньше")
    }

    func testParkedCarUnderBadSkyWritesNothing() {
        var fixes = [TrackTestKit.fix(east: 0, north: 0, speed: 0, after: 0, accuracy: 8)]
        for t in 1...300 {
            let jitter = Double((t * 37) % 80) - 40
            fixes.append(TrackTestKit.fix(east: jitter, north: -jitter, speed: 0,
                                          after: Double(t), accuracy: 150))
        }
        XCTAssertEqual(record(fixes).samples.count, 1, "грубая точка пишется только на ходу")
    }

    func testGoodFixStoresRawAccuracy() {
        let recorded = record([
            TrackTestKit.fix(east: 0, north: 0, speed: 10, after: 0, accuracy: 30),
            TrackTestKit.fix(east: 0, north: 10, speed: 10, after: 1, accuracy: 30),
        ])
        XCTAssertEqual(recorded.samples.last?.accuracy, 30)
    }

    func testCoarseSpeedSpikeDoesNotSetTheRecord() {
        var fixes = Array(drive(coarseWindow: nil).prefix(30))
        fixes.append(TrackTestKit.fix(east: 0, north: 310, speed: 40, after: 31, accuracy: 150))
        XCTAssertLessThan(record(fixes).maxSpeed, 15)
    }
}
