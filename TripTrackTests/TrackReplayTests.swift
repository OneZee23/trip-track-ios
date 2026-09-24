import XCTest
@testable import TripTrack

/// Приёмка спеки §5 на стенде.
@MainActor
final class TrackReplayTests: XCTestCase {
    func testCityEveningNoLongerTearsTheTrack() async {
        let old = await TrackReplay.run(SyntheticDrives.cityEvening(), recordingLimit: 65)
        let new = await TrackReplay.run(SyntheticDrives.cityEvening())
        XCTAssertGreaterThanOrEqual(old.recordedGaps, 5, "фикстура обязана повторять 8 сентября")
        XCTAssertEqual(new.recordedGaps, 0, "грубые фиксы закрыли все окна плохого неба")
        XCTAssertEqual(new.openGaps, 0)
        XCTAssertGreaterThan(new.coarsePoints, 0)
        XCTAssertEqual(new.distance, old.distance, accuracy: old.distance * 0.01, "одометр — в пределах 1 %")

        // На кварталах 400 м угол чаще целиком тонет в плохом окне — расхождение
        // с `old` растёт (до ~1.5 %, порог выше не держим на этой стороне), но
        // важно НАПРАВЛЕНИЕ: `new` обязан читать БЛИЖЕ к настоящему пройденному
        // пути, а не дальше от него (решение владельца по спеке §2.2).
        let truth = SyntheticDrives.trueDistance()
        let old400 = await TrackReplay.run(SyntheticDrives.cityEvening(side: 400), recordingLimit: 65)
        let new400 = await TrackReplay.run(SyntheticDrives.cityEvening(side: 400))
        XCTAssertLessThanOrEqual(
            abs(new400.distance - truth), abs(old400.distance - truth),
            "грубые фиксы в фильтре не должны уводить одометр от настоящего пути дальше, чем уводил старый конвейер")
    }

    func testTunnelIsFilledAndNotCounted() async {
        let old = await TrackReplay.run(SyntheticDrives.tunnel(), recordingLimit: 65)
        let new = await TrackReplay.run(SyntheticDrives.tunnel())
        XCTAssertEqual(new.recordedGaps, 1)
        XCTAssertEqual(new.openGaps, 0)
        XCTAssertGreaterThan(new.filledPoints, 0)
        XCTAssertEqual(new.distance, old.distance, accuracy: old.distance * 0.01)
    }

    func testSuspensionIsFilledAndNotCounted() async {
        let new = await TrackReplay.run(SyntheticDrives.suspension())
        XCTAssertEqual(new.recordedGaps, 1)
        XCTAssertEqual(new.openGaps, 0)
        XCTAssertGreaterThan(new.filledPoints, 0)
    }

    /// «Каждая дыра закрыта ровно одной достройкой» — с дорогой от заглушки.
    func testEachGapIsClosedByExactlyOneFill() async {
        let tunnel = await TrackReplay.run(SyntheticDrives.tunnel(), router: StubRoadRouter.straightLine())
        XCTAssertEqual(tunnel.openGaps, 0)
        XCTAssertEqual(tunnel.fillRuns, 1)
        let suspension = await TrackReplay.run(SyntheticDrives.suspension(), router: StubRoadRouter.straightLine())
        XCTAssertEqual(suspension.fillRuns, 1)
    }
}
