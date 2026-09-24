import XCTest
@testable import TripTrack

/// Шлюз фикса (спека §2.1): на записи отбрасывается только заведомо ложное.
/// Потолок 65 м выбрасывал фиксы, на которых висит вечерний город, и маршрут
/// 8 сентября рвался на куски; 65 м остаются правилом одометра, а не шлюза.
final class FixGateTests: XCTestCase {
    private func decide(_ acc: Double, age: Double = 0, speed: Double = 10,
                        recording: Bool = true,
                        limit: Double = FixGate.recordingAccuracyLimit) -> FixGate.Decision {
        FixGate.decide(horizontalAccuracy: acc, ageSeconds: age, speedMS: speed,
                       isRecording: recording, recordingLimit: limit)
    }

    func testRecordingAcceptsCoarseFixesUpToTwoHundredMetres() {
        XCTAssertEqual(decide(64), .accept)
        XCTAssertEqual(decide(120), .accept)
        XCTAssertEqual(decide(200), .accept)
    }

    func testRecordingRejectsBeyondTwoHundredMetres() {
        XCTAssertEqual(decide(201), .reject(.accuracy))
    }

    func testIdleKeepsItsHundredMetreCeiling() {
        XCTAssertEqual(decide(90, recording: false), .accept)
        XCTAssertEqual(decide(150, recording: false), .reject(.accuracy))
    }

    func testInvalidStaleAndImpossibleSpeedAreRejected() {
        XCTAssertEqual(decide(-1), .reject(.invalid))
        XCTAssertEqual(decide(10, age: 10), .reject(.stale))
        XCTAssertEqual(decide(10, speed: 90), .reject(.speed))
    }

    func testUnknownSpeedIsKept() {
        XCTAssertEqual(decide(10, speed: -1), .accept)
    }

    func testTheOldPipelineCanBeReplayed() {
        XCTAssertEqual(decide(70, limit: 65), .reject(.accuracy))
    }
}
