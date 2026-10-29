import XCTest
@testable import TripTrack

final class AutoRecordTriggerTests: XCTestCase {
    func testRawValuesStayCompatibleWithStorage() {
        XCTAssertEqual(AutoRecordTrigger.motionOrStereo.rawValue, "motionOrStereo")
        XCTAssertEqual(AutoRecordTrigger.stereoOnly.rawValue, "stereoOnly")
    }

    func testParsesStoredValues() {
        XCTAssertEqual(AutoRecordTrigger.parse("motionOrStereo"), .motionOrStereo)
        XCTAssertEqual(AutoRecordTrigger.parse("stereoOnly"), .stereoOnly)
    }

    func testMissingOrUnknownValueKeepsMotionEnabled() {
        XCTAssertEqual(AutoRecordTrigger.parse(nil), .motionOrStereo)
        XCTAssertEqual(AutoRecordTrigger.parse("unknown"), .motionOrStereo)
        XCTAssertEqual(AutoRecordTrigger.parse(""), .motionOrStereo)
    }
}
