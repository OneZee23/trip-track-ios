import XCTest
import SwiftUI
@testable import TripTrack

/// Locks the speed→colour scale that v0.5.7 extracted out of RouteMapView into
/// a single source shared with the on-map legend. The legend the user asked for
/// is only trustworthy if these thresholds stay identical to what the polyline
/// renderer used before the refactor — that's exactly what this guards.
final class SpeedColorScaleTests: XCTestCase {

    /// The pre-refactor inline thresholds (km/h): <50 / 50–90 / 90–110 / 110+.
    private func legacyZone(_ kmh: Double) -> Int {
        switch kmh {
        case ..<50: return 0
        case 50..<90: return 1
        case 90..<110: return 2
        default: return 3
        }
    }

    func testZoneMatchesLegacyThresholdsAcrossRange() {
        // Sweep 0–200 km/h; compare against the legacy switch using the SAME
        // m/s→km/h conversion the implementation performs, so float boundaries
        // (e.g. exactly 50) can't make this flaky.
        for tenthsKmh in 0...2000 {
            let kmh = Double(tenthsKmh) / 10.0
            let ms = kmh / 3.6
            XCTAssertEqual(
                SpeedColorScale.zone(forSpeedMS: ms),
                legacyZone(max(0, ms) * 3.6),
                "zone drift at \(kmh) km/h"
            )
        }
    }

    func testInteriorSpeedsLandInExpectedZones() {
        XCTAssertEqual(SpeedColorScale.zone(forSpeedMS: 12.5), 0)   // 45 km/h
        XCTAssertEqual(SpeedColorScale.zone(forSpeedMS: 15.277), 1) // 55 km/h
        XCTAssertEqual(SpeedColorScale.zone(forSpeedMS: 26.388), 2) // 95 km/h
        XCTAssertEqual(SpeedColorScale.zone(forSpeedMS: 36.111), 3) // 130 km/h
    }

    func testNegativeAndZeroSpeedClampToSlowestZone() {
        XCTAssertEqual(SpeedColorScale.zone(forSpeedMS: 0), 0)
        XCTAssertEqual(SpeedColorScale.zone(forSpeedMS: -10), 0,
                       "unknown/negative speed must not fall through to the fast band")
    }

    func testColourMatchesZoneBand() {
        // The renderer's stroke colour must be exactly the band for that zone.
        XCTAssertEqual(SpeedColorScale.uiColor(forSpeedMS: 12.5),
                       SpeedColorScale.bands[0].uiColor)
        XCTAssertEqual(SpeedColorScale.uiColor(forSpeedMS: 36.111),
                       SpeedColorScale.bands[3].uiColor)
    }

    func testLegendRowsCoverEveryBandSlowToFast() {
        let rows = SpeedColorScale.legendRows()
        XCTAssertEqual(rows.count, SpeedColorScale.bands.count)
        XCTAssertEqual(rows.map(\.range), ["0–50", "50–90", "90–110", "110+"])
    }
}
