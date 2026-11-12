import XCTest
@testable import TripTrack

final class HiddenPartsEditorModelTests: XCTestCase {
    func testApplyStagesAndCancelRestoresSavedValues() {
        let original = TripHiddenParts(startMetres: 200, endMetres: 0)
        var model = HiddenPartsEditorModel(parts: original)
        model.setStartMetres(1_000)
        XCTAssertEqual(model.apply().startMetres, 1_000)
        XCTAssertEqual(model.saved.startMetres, 200)
        model.cancel()
        XCTAssertEqual(model.draft, original)
    }

    func testOverlappingSectionsMergeAndPreserveOuterBounds() {
        let origin = Date(timeIntervalSince1970: 1_000)
        var model = HiddenPartsEditorModel(parts: TripHiddenParts())
        model.addSection(from: origin, to: origin.addingTimeInterval(60))
        model.addSection(from: origin.addingTimeInterval(45), to: origin.addingTimeInterval(90))
        XCTAssertEqual(model.draft.sections.count, 1)
        XCTAssertEqual(model.draft.sections[0].from, origin)
        XCTAssertEqual(model.draft.sections[0].to, origin.addingTimeInterval(90))
    }

    func testEdgeValuesAreStoredAsMetres() {
        var model = HiddenPartsEditorModel(parts: TripHiddenParts())
        model.setStartMetres(500)
        model.setEndMetres(1_000)
        XCTAssertEqual(model.apply().startMetres, 500)
        XCTAssertEqual(model.apply().endMetres, 1_000)
    }

    func testNumbersPreviewUsesVisibleRuns() {
        let start = Date(timeIntervalSince1970: 1_000)
        let points = (0..<8).map { index in
            TrackPoint(latitude: 40, longitude: -3 + Double(index) * 0.001,
                       horizontalAccuracy: 5, timestamp: start.addingTimeInterval(Double(index) * 60))
        }
        let full = HiddenPartsEditorModel.preview(points: points, recordingBreaks: [], parts: TripHiddenParts(), defaultEdgeMetres: nil, zone: nil)
        let masked = HiddenPartsEditorModel.preview(
            points: points, recordingBreaks: [],
            parts: TripHiddenParts(sections: [HiddenSection(id: UUID(), from: points[3].timestamp, to: points[4].timestamp)]),
            defaultEdgeMetres: nil, zone: nil)
        XCTAssertGreaterThan(masked.distanceMetres, 0)
        XCTAssertLessThan(masked.distanceMetres, full.distanceMetres)
        XCTAssertLessThan(masked.duration, full.duration)
    }

    func testQuestionIsAskedOnlyWhenIdleAndBeforeFirstPublishAfterDismissal() {
        XCTAssertTrue(HiddenEdgesQuestionPolicy.shouldAskOnOpen(answered: false, recording: false, anotherSheetOpen: false))
        XCTAssertFalse(HiddenEdgesQuestionPolicy.shouldAskOnOpen(answered: false, recording: true, anotherSheetOpen: false))
        XCTAssertFalse(HiddenEdgesQuestionPolicy.shouldAskOnOpen(answered: false, recording: false, anotherSheetOpen: true))
        XCTAssertFalse(HiddenEdgesQuestionPolicy.shouldAskOnOpen(answered: true, recording: false, anotherSheetOpen: false))
        XCTAssertTrue(HiddenEdgesQuestionPolicy.shouldAskBeforePublish(pending: true, answered: false))
        XCTAssertFalse(HiddenEdgesQuestionPolicy.shouldAskBeforePublish(pending: true, answered: true))
    }
}
