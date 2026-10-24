import XCTest
@testable import TripTrack

/// «Bluetooth выключен» — только по ответу системы (владелец на 0.9.1 (95),
/// 24 окт 2026: карточка машины писала «выключен» при включённом Bluetooth,
/// потому что без автозапуска состояние не спрашивал никто).
final class BluetoothPowerStateTests: XCTestCase {
    func testUnknownStateIsNotOff() {
        let detector = BluetoothDetector()
        XCTAssertEqual(detector.powerState, .unknown)
        XCTAssertFalse(detector.isBluetoothOff, "Not asked yet is not «off»")
        XCTAssertFalse(detector.isBluetoothAvailable)
    }

    func testStopMonitoringForgetsTheState() {
        let detector = BluetoothDetector()
        detector.stopMonitoring()
        XCTAssertEqual(detector.powerState, .unknown)
        XCTAssertFalse(detector.isBluetoothOff)
    }
}
