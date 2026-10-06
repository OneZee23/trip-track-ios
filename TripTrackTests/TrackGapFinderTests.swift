import XCTest
@testable import TripTrack

/// Дыра — соседние НЕдостроенные точки, ≥ 10 с И ≥ 150 м (спека §2.3): те же
/// числа, что в замере по поездкам 8 сентября.
final class TrackGapFinderTests: XCTestCase {
    private func p(_ north: Double, _ s: Double, filled: Bool = false,
                   segment: Int = 0) -> TrackGapFinder.Point {
        let c = TrackTestKit.coordinate(east: 0, north: north)
        return .init(latitude: c.latitude, longitude: c.longitude,
                     timestamp: TrackTestKit.epoch.addingTimeInterval(s), isInterpolated: filled,
                     recordingSegmentIndex: segment)
    }

    func testLongAndSlowIsAGap() {
        XCTAssertEqual(TrackGapFinder.openGaps(in: [p(0, 0), p(200, 12)]).count, 1)
    }

    func testShortDistanceIsNotAGap() {
        XCTAssertTrue(TrackGapFinder.openGaps(in: [p(0, 0), p(100, 12)]).isEmpty)
    }

    func testShortTimeIsNotAGap() {
        XCTAssertTrue(TrackGapFinder.openGaps(in: [p(0, 0), p(300, 5)]).isEmpty)
    }

    /// Review Focus 5: дыра, уже закрытая достройкой — своей или пришедшей
    /// пулом со второго телефона, — второй раз не открывается.
    func testFilledGapIsNotOpen() {
        let points = [p(0, 0), p(100, 6, filled: true), p(200, 12)]
        XCTAssertTrue(TrackGapFinder.openGaps(in: points).isEmpty)
        XCTAssertEqual(TrackGapFinder.gaps(in: points, includeFilled: true).count, 1)
    }

    func testUnsortedInputIsHandled() {
        XCTAssertEqual(TrackGapFinder.openGaps(in: [p(200, 12), p(0, 0)]).count, 1)
    }

    func testExplicitPauseIsNotAnOpenOrPreviouslyFilledGPSGap() {
        let paused = [p(0, 0), p(200, 60, segment: 1)]
        XCTAssertTrue(TrackGapFinder.openGaps(in: paused).isEmpty)
        XCTAssertTrue(TrackGapFinder.gaps(in: paused, includeFilled: true).isEmpty)
    }

    func testGPSGapInsideResumedSectionStillFills() {
        let points = [p(0, 0), p(200, 60, segment: 1), p(400, 80, segment: 1)]
        let gaps = TrackGapFinder.openGaps(in: points)
        XCTAssertEqual(gaps.count, 1)
        XCTAssertEqual(gaps.first?.from.recordingSegmentIndex, 1)
        XCTAssertEqual(gaps.first?.seconds, 20)
    }
}
