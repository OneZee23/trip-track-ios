import CoreLocation
import XCTest
@testable import TripTrack

final class HiddenPartsGeometryTests: XCTestCase {
    func testParkedHeadAndJitteredTailNeedTwoMinutesAndStayWithinRadius() {
        let points = parkedTrip()
        let parked = HiddenPartsGeometry.parkedBoundaries(points: points)
        XCTAssertEqual(parked.departure, 2)
        XCTAssertEqual(parked.arrival, 5)
        XCTAssertEqual(HiddenPartsGeometry.parkedBoundaries(points: straightTrip(stepMetres: 100, count: 8)),
                       .init(departure: nil, arrival: nil))

        let shortTail = Array(points.prefix(7))
        XCTAssertNil(HiddenPartsGeometry.parkedBoundaries(points: shortTail).arrival)

        let shortHead = [point(at: 0, time: 0), point(at: 10, time: 60), point(at: 200, time: 120)]
        XCTAssertNil(HiddenPartsGeometry.parkedBoundaries(points: shortHead).departure)

        var leavesRadius = points
        leavesRadius[6] = point(at: 700, time: 420)
        XCTAssertNil(HiddenPartsGeometry.parkedBoundaries(points: leavesRadius).arrival)
    }

    func testRecordingBreaksAreIncludedInTheSharedResolverPrefix() {
        let points = straightTrip(stepMetres: 100, count: 5)
        let prefix = HiddenPartsGeometry.prefix(points: points,
                                                recordingBreaks: [points[2].timestamp.addingTimeInterval(-1)])
        XCTAssertEqual(prefix.count, 5)
        for (actual, expected) in zip(prefix, [0.0, 100, 100, 200, 300]) {
            XCTAssertEqual(actual, expected, accuracy: 2)
        }
    }

    func testStoredStartAndEndMetresReproduceEveryRequestedHiddenPoint() {
        let points = straightTrip(stepMetres: 100, count: 12)
        let prefix = HiddenPartsGeometry.prefix(points: points, recordingBreaks: [])
        let start = HiddenPartsGeometry.startBoundary(near: 4, prefix: prefix)
        let end = HiddenPartsGeometry.endBoundary(near: 7, prefix: prefix)

        XCTAssertEqual(start.index, 4)
        XCTAssertEqual(end.index, 7)
        XCTAssertEqual(hiddenIndices(points: points, startMetres: start.metres, endMetres: 0), Set(0..<4))
        XCTAssertEqual(hiddenIndices(points: points, startMetres: 0, endMetres: end.metres), Set(8..<12))
        XCTAssertEqual(hiddenIndices(points: points, startMetres: 0, endMetres: 0), [])
    }

    func testGhostHandlesStoreZeroAndKeepEveryPointVisible() {
        let points = straightTrip(stepMetres: 75, count: 16)
        let hidden = hiddenIndices(points: points, startMetres: 0, endMetres: 0)
        XCTAssertTrue(hidden.isEmpty)
        XCTAssertEqual(HiddenPartsGeometry.startBoundary(near: 0, prefix: HiddenPartsGeometry.prefix(points: points, recordingBreaks: [])).metres, 0)
        XCTAssertEqual(HiddenPartsGeometry.endBoundary(near: points.count - 1, prefix: HiddenPartsGeometry.prefix(points: points, recordingBreaks: [])).metres, 0)
    }

    func testStoredParkingMetresHideTheFullParkedPrefixAndSuffix() {
        let points = parkedTrip()
        let prefix = HiddenPartsGeometry.prefix(points: points, recordingBreaks: [])
        let parked = HiddenPartsGeometry.parkedBoundaries(points: points)
        let start = HiddenPartsGeometry.startBoundary(near: (parked.departure ?? 0) + 1, prefix: prefix)
        let end = HiddenPartsGeometry.endBoundary(near: (parked.arrival ?? points.count - 1) - 1, prefix: prefix)

        XCTAssertEqual(hiddenIndices(points: points, startMetres: start.metres, endMetres: 0), Set(0...2))
        XCTAssertEqual(hiddenIndices(points: points, startMetres: 0, endMetres: end.metres), Set(5..<points.count))
    }

    func testEqualPrefixesKeepTheBoundaryPointVisible() {
        let points = [point(at: 0, time: 0), point(at: 100, time: 30), point(at: 100, time: 60),
                      point(at: 200, time: 90), point(at: 300, time: 120)]
        let prefix = HiddenPartsGeometry.prefix(points: points, recordingBreaks: [])
        let boundary = HiddenPartsGeometry.startBoundary(near: 2, prefix: prefix)
        let hidden = hiddenIndices(points: points, startMetres: boundary.metres, endMetres: 0)
        XCTAssertTrue(hidden.contains(0))
        XCTAssertFalse(hidden.contains(boundary.index))
    }

    func testDetentsAndVisibleRouteBounds() {
        XCTAssertEqual(HiddenPartsGeometry.detent(near: 230), 200)
        XCTAssertEqual(HiddenPartsGeometry.detent(near: 235), 200)
        XCTAssertEqual(HiddenPartsGeometry.detent(near: 535), 500)
        XCTAssertNil(HiddenPartsGeometry.detent(near: 240))
        XCTAssertNil(HiddenPartsGeometry.detent(near: 236))

        let prefix = (0...10).map { Double($0 * 50) }
        let latestStart = HiddenPartsGeometry.maximumStartIndex(endingAt: 8, prefix: prefix)
        let earliestEnd = HiddenPartsGeometry.minimumEndIndex(startingAt: 2, prefix: prefix)
        XCTAssertGreaterThanOrEqual(prefix[8] - prefix[latestStart], 100)
        XCTAssertGreaterThanOrEqual(prefix[earliestEnd] - prefix[2], 100)
    }

    func testContinuitySearchStaysOnTheCurrentPassUntilItIsFarFromTheFinger() {
        let points = (0...60).map { CGPoint(x: CGFloat($0 * 4), y: 0) } +
            (1...60).reversed().map { CGPoint(x: CGFloat($0 * 4), y: 3) }
        let finger = CGPoint(x: 28 * 4, y: 0)
        let result = HiddenPartsGeometry.nearestIndex(to: finger, currentIndex: 28,
                                                      allowed: 0...(points.count - 1),
                                                      pointAtIndex: { points[$0] })
        XCTAssertEqual(result, 28)

        let draggedFar = HiddenPartsGeometry.nearestIndex(to: CGPoint(x: -100, y: 0), currentIndex: 50,
                                                           allowed: 0...100,
                                                           pointAtIndex: { CGPoint(x: CGFloat($0), y: 0) })
        XCTAssertEqual(draggedFar, 0)
    }

    func testSectionCreationClampsAndRejectsOverlapsOrShortRanges() {
        let prefix = (0...20).map { Double($0 * 50) }
        let section = HiddenPartsGeometry.sectionRange(around: 10, visibleStart: 0, visibleEnd: 20,
                                                       prefix: prefix, occupied: [])
        XCTAssertNotNil(section)
        XCTAssertEqual(section?.lowerBound, 8)
        XCTAssertEqual(section?.upperBound, 12)
        XCTAssertGreaterThanOrEqual(prefix[section!.upperBound] - prefix[section!.lowerBound], 40)

        let clamped = HiddenPartsGeometry.sectionRange(around: 0, visibleStart: 0, visibleEnd: 20,
                                                       prefix: prefix, occupied: [])
        XCTAssertEqual(clamped?.lowerBound, 1)

        XCTAssertNil(HiddenPartsGeometry.sectionRange(around: 10, visibleStart: 0, visibleEnd: 20,
                                                       prefix: prefix, occupied: [8...12]))
        XCTAssertNil(HiddenPartsGeometry.sectionRange(around: 2, visibleStart: 0, visibleEnd: 3,
                                                       prefix: [0, 10, 20, 30], occupied: []))
    }

    func testSectionMergeAndUndoRestoreTheOriginalTimeRange() {
        let origin = Date(timeIntervalSince1970: 10_000)
        let first = HiddenSection(id: UUID(), from: origin, to: origin.addingTimeInterval(60))
        let second = HiddenSection(id: UUID(), from: origin.addingTimeInterval(45), to: origin.addingTimeInterval(90))
        let merged = HiddenPartsGeometry.mergedSections([first, second])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].from, first.from)
        XCTAssertEqual(merged[0].to, second.to)

        var model = HiddenPartsEditorModel(parts: TripHiddenParts(sections: [first]))
        let undoSections = model.draft.sections
        model.removeSection(first.id)
        XCTAssertTrue(model.draft.sections.isEmpty)
        model.draft.sections = HiddenPartsGeometry.mergedSections(undoSections)
        XCTAssertEqual(model.draft.sections, undoSections)
        XCTAssertEqual(model.draft.sections[0].from, first.from)
        XCTAssertEqual(model.draft.sections[0].to, first.to)
        XCTAssertTrue(HiddenPartsGeometry.sectionNeedsRemoval(from: 1, to: 1, prefix: [0, 20, 80]))
        XCTAssertFalse(HiddenPartsGeometry.sectionNeedsRemoval(from: 1, to: 2, prefix: [0, 20, 80]))
    }

    func testResolverPerformanceForTenThousandPoints() {
        let points = straightTrip(stepMetres: 25, count: 10_000)
        measure {
            let resolution = HiddenPartsResolver.resolve(points: points, recordingBreaks: [],
                                                         startMetres: 500, endMetres: 1_000,
                                                         sections: [], zone: nil)
            XCTAssertGreaterThan(resolution.visiblePoints.count, 0)
        }
    }

    private func hiddenIndices(points: [TrackPoint], startMetres: Int, endMetres: Int) -> Set<Int> {
        let result = HiddenPartsResolver.resolve(points: points, recordingBreaks: [],
                                                startMetres: startMetres, endMetres: endMetres,
                                                sections: [], zone: nil)
        let visible = Set(result.visiblePoints.map(\.id))
        return Set(points.indices.filter { !visible.contains(points[$0].id) })
    }

    private func straightTrip(stepMetres: Double, count: Int) -> [TrackPoint] {
        (0..<count).map { index in point(at: Double(index) * stepMetres, time: Double(index * 30)) }
    }

    private func parkedTrip() -> [TrackPoint] {
        [point(at: 0, time: 0), point(at: 10, time: 60), point(at: 20, time: 120),
         point(at: 200, time: 180), point(at: 400, time: 240), point(at: 500, time: 300),
         point(at: 520, time: 360), point(at: 540, time: 420), point(at: 530, time: 480)]
    }

    private func point(at metres: Double, time: TimeInterval) -> TrackPoint {
        TrackPoint(latitude: metres / 111_195, longitude: 0, horizontalAccuracy: 5,
                   timestamp: Date(timeIntervalSince1970: 1_000 + time))
    }
}
