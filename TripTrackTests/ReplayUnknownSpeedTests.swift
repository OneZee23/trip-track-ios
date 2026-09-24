import XCTest
import CoreLocation
@testable import TripTrack

/// Машинка реплея проезжает пунктир (спека §2.4), но пузырь скорости там
/// прячется: «0 км/ч» на ходу было бы враньём.
@MainActor
final class ReplayUnknownSpeedTests: XCTestCase {
    func testTheBubbleKnowsWhenSpeedIsUnknown() {
        let engine = TripReplayEngine()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let coords = (0..<5).map { CLLocationCoordinate2D(latitude: 0, longitude: Double($0) * 0.001) }
        let times = (0..<5).map { t0.addingTimeInterval(Double($0) * 10) }
        engine.configure(coords: coords, timestamps: times, speeds: [10, 10, -1, -1, 10])

        engine.seek(to: 0.55)   // 22 с — между второй и третьей точкой
        XCTAssertFalse(engine.currentSpeedKnown)

        engine.seek(to: 0.05)   // 2 с — между нулевой и первой
        XCTAssertTrue(engine.currentSpeedKnown)
        XCTAssertEqual(engine.currentSpeedMS, 10, accuracy: 0.001)
    }
}
