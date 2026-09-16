import XCTest
import CoreLocation
@testable import TripTrack

/// Плашка реплея обязана иметь ОДНО явное состояние.
///
/// Поломка, из-за которой эти тесты написаны: «×» на полноэкранной карте горел
/// сразу при входе, будто идёт воспроизведение, и нажатие на него ничего не
/// меняло. Состояния не было — плашка выводила его из полей движка
/// (`isPlaying || progress > 0 || headCoord != nil`), а `configure` рисовал
/// нулевой кадр и оставлял `headCoord` не пустым до всякого нажатия.
final class ReplayBarStateTests: XCTestCase {

    // MARK: - Чистый редьюсер

    func testEntryIsIdleAndHidesStop() {
        XCTAssertFalse(ReplayBarState.idle.showsStop)
        XCTAssertFalse(ReplayBarState.idle.showsPauseIcon)
        XCTAssertFalse(ReplayBarState.idle.showsHead)
    }

    func testTapPlayFromIdleStartsPlaying() {
        XCTAssertEqual(ReplayBarState.reduce(.idle, .tapPlayPause), .playing)
        XCTAssertTrue(ReplayBarState.playing.showsStop)
        XCTAssertTrue(ReplayBarState.playing.showsPauseIcon)
    }

    func testTapPlayTogglesBetweenPlayingAndPaused() {
        XCTAssertEqual(ReplayBarState.reduce(.playing, .tapPlayPause), .paused)
        XCTAssertEqual(ReplayBarState.reduce(.paused, .tapPlayPause), .playing)
        XCTAssertTrue(ReplayBarState.paused.showsStop)
        XCTAssertFalse(ReplayBarState.paused.showsPauseIcon)
    }

    func testStopFromAnyStateReturnsToIdle() {
        XCTAssertEqual(ReplayBarState.reduce(.playing, .tapStop), .idle)
        XCTAssertEqual(ReplayBarState.reduce(.paused, .tapStop), .idle)
        XCTAssertEqual(ReplayBarState.reduce(.idle, .tapStop), .idle)
    }

    func testScrubFromIdleEntersPaused() {
        XCTAssertEqual(ReplayBarState.reduce(.idle, .scrub), .paused)
    }

    /// Паузу на время жеста плашка ставит сама — редьюсер её не отменяет и не
    /// вводит.
    func testScrubLeavesRunningStatesAlone() {
        XCTAssertEqual(ReplayBarState.reduce(.playing, .scrub), .playing)
        XCTAssertEqual(ReplayBarState.reduce(.paused, .scrub), .paused)
    }

    func testReachingTheEndPausesOnTheLastFrame() {
        XCTAssertEqual(ReplayBarState.reduce(.playing, .reachedEnd), .paused)
        XCTAssertEqual(ReplayBarState.reduce(.paused, .reachedEnd), .paused)
        XCTAssertEqual(ReplayBarState.reduce(.idle, .reachedEnd), .idle)
    }

    // MARK: - Движок ходит теми же переходами

    private func line(_ n: Int) -> [CLLocationCoordinate2D] {
        (0..<n).map { CLLocationCoordinate2D(latitude: 0, longitude: Double($0) * 0.001) }
    }

    private func times(_ n: Int) -> [Date] {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<n).map { t0.addingTimeInterval(Double($0) * 10) }
    }

    @MainActor
    private func configured(_ n: Int = 11) -> TripReplayEngine {
        let engine = TripReplayEngine()
        engine.configure(coords: line(n), timestamps: times(n), speeds: [])
        return engine
    }

    /// Вход на экран: ни машинки, ни «×», бегунок на нуле.
    @MainActor
    func testConfigureLeavesTheEngineIdleWithNoHead() {
        let engine = configured()
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertFalse(engine.phase.showsStop)
        XCTAssertNil(engine.headCoord)
        XCTAssertEqual(engine.trailIndex, -1)
        XCTAssertEqual(engine.progress, 0, accuracy: 1e-9)
    }

    @MainActor
    func testPlayShowsTheHeadAndTheStopButton() {
        let engine = configured()
        engine.play()
        XCTAssertEqual(engine.phase, .playing)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertTrue(engine.phase.showsStop)
        XCTAssertNotNil(engine.headCoord)
        engine.stop()
    }

    @MainActor
    func testStopFromPlayingReturnsToIdleAndClearsTheMap() {
        let engine = configured()
        engine.play()
        engine.stop()
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertFalse(engine.phase.showsStop)
        XCTAssertNil(engine.headCoord)
        XCTAssertEqual(engine.trailIndex, -1)
        XCTAssertEqual(engine.progress, 0, accuracy: 1e-9)
        XCTAssertEqual(engine.distanceFraction, 0, accuracy: 1e-9)
    }

    @MainActor
    func testStopFromPausedReturnsToIdle() {
        let engine = configured()
        engine.seek(to: 0.5)
        engine.pause()
        XCTAssertEqual(engine.phase, .paused)
        engine.stop()
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertNil(engine.headCoord)
    }

    /// Подмотка с нетронутого экрана — это пауза на выбранном кадре, и
    /// машинка там уже есть.
    @MainActor
    func testScrubFromIdlePausesAtThatPosition() {
        let engine = configured()
        engine.seek(to: 0.4)
        XCTAssertEqual(engine.phase, .paused)
        XCTAssertTrue(engine.phase.showsStop)
        XCTAssertEqual(engine.progress, 0.4, accuracy: 1e-9)
        XCTAssertNotNil(engine.headCoord)
    }

    /// «Пауза» зовут и жест подмотки, и тап по маршруту — из `idle` она не
    /// имеет права ничего запустить.
    @MainActor
    func testPauseFromIdleStaysIdle() {
        let engine = configured()
        engine.pause()
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertNil(engine.headCoord)
    }

    /// Отметки на шкале — позиции, а не прогресс: «×» их не забирает.
    @MainActor
    func testStopKeepsHoldMarkersOnTheScrubber() {
        let engine = configured()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        engine.setHolds(at: [t0.addingTimeInterval(40)])
        XCTAssertEqual(engine.holdFractions.count, 1)
        engine.play()
        engine.stop()
        XCTAssertEqual(engine.holdFractions.count, 1)
        XCTAssertNil(engine.holdingIndex)
    }

    @MainActor
    func testTogglePlayWalksTheSamePathAsTheReducer() {
        let engine = configured()
        engine.togglePlay()
        XCTAssertEqual(engine.phase, .playing)
        engine.togglePlay()
        XCTAssertEqual(engine.phase, .paused)
        engine.togglePlay()
        XCTAssertEqual(engine.phase, .playing)
        engine.stop()
    }
}
