import XCTest
@testable import TripTrack

final class HiddenPhotoSyncTests: XCTestCase {
    func testHidingServerCopySchedulesDeletion() {
        XCTAssertEqual(
            HiddenPhotoSync.decision(isHidden: true, status: .uploaded, hasServerCopy: true),
            .removeFromServer)
    }

    func testHidingLocalCopyDoesNotScheduleServerDeletion() {
        XCTAssertEqual(
            HiddenPhotoSync.decision(isHidden: true, status: .localOnly, hasServerCopy: false),
            .keep)
    }

    func testVisibleAgainSchedulesUpload() {
        XCTAssertEqual(
            HiddenPhotoSync.decision(isHidden: false, status: .hiddenByPrivacy, hasServerCopy: true),
            .uploadAgain)
    }

    func testHiddenPhotoStatePreservesLocalCopyDuringPull() {
        XCTAssertTrue(HiddenPhotoSync.preservesLocalCopyDuringPull(
            isHiddenLocally: false, status: .hiddenByPrivacy))
        XCTAssertTrue(HiddenPhotoSync.preservesLocalCopyDuringPull(
            isHiddenLocally: false, status: .localOnly))
        XCTAssertTrue(HiddenPhotoSync.preservesLocalCopyDuringPull(
            isHiddenLocally: true, status: .uploaded))
        XCTAssertFalse(HiddenPhotoSync.preservesLocalCopyDuringPull(
            isHiddenLocally: false, status: .uploaded))
    }
}
