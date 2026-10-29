import XCTest
@testable import TripTrack

final class AutoTripTriggerPolicyTests: XCTestCase {
    func testMotionSignalStartsTripTable() {
        let cases: [(trigger: AutoRecordTrigger, automotive: Bool, stereo: Bool, starts: Bool)] = [
            (.motionOrStereo, false, false, false),
            (.motionOrStereo, false, true, false),
            (.motionOrStereo, true, false, true),
            (.motionOrStereo, true, true, true),
            (.stereoOnly, false, false, false),
            (.stereoOnly, false, true, true),
            (.stereoOnly, true, false, false),
            (.stereoOnly, true, true, true)
        ]

        for row in cases {
            XCTAssertEqual(
                AutoTripPolicy.motionSignalStartsTrip(
                    trigger: row.trigger,
                    isAutomotive: row.automotive,
                    linkedStereoConnected: row.stereo
                ),
                row.starts,
                "\(row.trigger.rawValue), automotive=\(row.automotive), stereo=\(row.stereo)"
            )
        }
    }
}
