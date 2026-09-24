import XCTest
@testable import TripTrack

/// «Кто начал, тот и заканчивает» (спека §3.4). Пауза по-прежнему сильнее.
final class AutoTripDraftPolicyTests: XCTestCase {
    func testStopModeTable() {
        XCTAssertEqual(AutoTripPolicy.stopMode(settings: .remind, tripIsDraft: true), .auto)
        XCTAssertEqual(AutoTripPolicy.stopMode(settings: .remind, tripIsDraft: false), .remind)
        XCTAssertEqual(AutoTripPolicy.stopMode(settings: .off, tripIsDraft: true), .auto)
        XCTAssertEqual(AutoTripPolicy.stopMode(settings: .auto, tripIsDraft: false), .auto)
    }

    func testDraftStopsOnDisconnectButPauseStillWins() {
        let mode = AutoTripPolicy.stopMode(settings: .remind, tripIsDraft: true)
        XCTAssertEqual(AutoTripPolicy.onBluetoothDisconnect(
            mode: mode, isRecording: true, isPaused: false, isIdleBeyondFastStop: false,
            tripDistance: 5000, tripDuration: 900, autoStopTimeout: 3), .stopNow)
        XCTAssertEqual(AutoTripPolicy.onBluetoothDisconnect(
            mode: mode, isRecording: true, isPaused: true, isIdleBeyondFastStop: true,
            tripDistance: 5000, tripDuration: 900, autoStopTimeout: 3), .ignore)
    }

    func testManualTripInRemindStillOnlyAsks() {
        let mode = AutoTripPolicy.stopMode(settings: .remind, tripIsDraft: false)
        XCTAssertEqual(AutoTripPolicy.onBluetoothDisconnect(
            mode: mode, isRecording: true, isPaused: false, isIdleBeyondFastStop: true,
            tripDistance: 5000, tripDuration: 900, autoStopTimeout: 3), .promptOnly)
    }
}
