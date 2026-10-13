import CoreLocation
import MapKit
import XCTest
@testable import TripTrack

/// Coarse levels join runs that meet end to start (13 Oct 2026).
///
/// A 25 600 km public map reached the vein and the path index as 9 735
/// two-vertex runs, one per 5 km tile, and the phone ran hot redrawing them.
/// Joining must not change a single segment: the fog, the width and the
/// kilometres stay exactly the same.
final class RevealedLayerStitchTests: XCTestCase {
    private func c(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private struct Segment: Hashable { let a, b, c, d: Double }

    private func segments(_ runs: [[CLLocationCoordinate2D]]) -> [Segment] {
        runs.flatMap { run in
            zip(run, run.dropFirst()).map {
                Segment(a: $0.latitude, b: $0.longitude, c: $1.latitude, d: $1.longitude)
            }
        }
    }

    func testTileCutRoadBecomesOneLine() {
        let runs = (0..<10).map { i in [c(55, 37 + Double(i) * 0.1), c(55, 37 + Double(i + 1) * 0.1)] }
        let joined = RevealedLayer.stitch(runs.shuffled())
        XCTAssertEqual(joined.count, 1)
        XCTAssertEqual(joined[0].first?.longitude ?? 0, 37, accuracy: 1e-12)
        XCTAssertEqual(joined[0].last?.longitude ?? 0, 38, accuracy: 1e-12)
        XCTAssertEqual(Set(segments(joined)), Set(segments(runs)))
    }

    func testSeparateRoadsStaySeparate() {
        let runs = [[c(55, 37), c(55, 37.1)], [c(56, 40), c(56, 40.1)]]
        XCTAssertEqual(RevealedLayer.stitch(runs).count, 2)
    }

    func testBranchKeepsEverySegment() {
        let runs = [[c(55, 37), c(55, 37.1)], [c(55, 37.1), c(55, 37.2)], [c(55, 37.1), c(55.1, 37.1)]]
        let joined = RevealedLayer.stitch(runs)
        XCTAssertEqual(joined.count, 2)
        XCTAssertEqual(segments(joined).count, 3)
        XCTAssertEqual(Set(segments(joined)), Set(segments(runs)))
    }

    func testLoopIsNotLost() {
        let runs = [[c(55, 37), c(55, 37.1)], [c(55, 37.1), c(55.1, 37.1)], [c(55.1, 37.1), c(55, 37)]]
        let joined = RevealedLayer.stitch(runs)
        XCTAssertEqual(Set(segments(joined)), Set(segments(runs)))
        XCTAssertEqual(segments(joined).count, 3)
    }

    func testLayerKeepsKilometresAndFineRunsWhileCoarseLinesShrink() {
        // A long road cut into tile-sized runs the way `RevealBuilder` cuts
        // it: the next run starts on the very point where the last one ended.
        let road = (0...800).map { i in c(55 + sin(Double(i) * 0.05) * 0.01, 37 + Double(i) * 0.004) }
        let runs = stride(from: 0, to: 800, by: 20).map { Array(road[$0...($0 + 20)]) }
        XCTAssertEqual(runs.count, 40)
        let layer = RevealedLayer.build(runs: runs, cellCount: 0, atlas: nil)
        XCTAssertEqual(layer.fine.polylines.count, 40, "Street level is never joined")
        XCTAssertLessThan(layer.far.polylines.count, 40)
        XCTAssertLessThan(layer.mid.polylines.count, 40)
        let unjoinedKm = RevealedLayer.openedMetres(runs: runs) / 1000
        XCTAssertEqual(layer.openedKm, unjoinedKm, accuracy: 1e-9, "Kilometres come from fine runs")
    }
}
