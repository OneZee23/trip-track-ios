import AVFoundation
import XCTest
@testable import TripTrack

final class AudioRouteDetectorTests: XCTestCase {
    func testCarStereoPorts() {
        let ports: [AVAudioSession.Port] = [.carAudio, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE]
        for port in ports {
            XCTAssertTrue(AudioRouteDetector.isCarStereoPort(port), port.rawValue)
        }
    }

    func testOtherAudioPortsAreNotCarStereos() {
        let ports: [AVAudioSession.Port] = [.builtInSpeaker, .headphones, .builtInReceiver]
        for port in ports {
            XCTAssertFalse(AudioRouteDetector.isCarStereoPort(port), port.rawValue)
        }
    }
}
