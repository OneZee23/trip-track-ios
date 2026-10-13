import XCTest
@testable import TripTrack

/// Раскрытие карты поездки: герой → весь экран и обратно.
///
/// Поломка, из-за которой эти тесты написаны: заход на полный экран строил
/// ВТОРУЮ `MKMapView` за едущей системной шторкой — разрез маршрута по
/// скорости, оверлеи, растрирование картинок аннотаций и первый растр
/// тумана, — и на устройстве это читалось как «тяжёлая анимация».
/// Состояние перехода живёт чистым типом, чтобы видимость хрома и целевой
/// кадр проверялись здесь, а не глазами на телефоне.
final class MapExpansionTests: XCTestCase {

    // MARK: - Состояния

    func testCollapsedIsTheOnlyStateWithoutAFullscreenLayer() {
        XCTAssertFalse(MapExpansionState.collapsed.isPresented)
        for state in MapExpansionState.allCases where state != .collapsed {
            XCTAssertTrue(state.isPresented, "\(state) обязан быть в дереве")
        }
    }

    /// Mount at final size before fading in; keep it mounted while fading out.
    func testOnlyExpandedTargetsVisibleOpacity() {
        XCTAssertFalse(MapExpansionState.collapsed.isVisible)
        XCTAssertFalse(MapExpansionState.expanding.isVisible)
        XCTAssertTrue(MapExpansionState.expanded.isVisible)
        XCTAssertFalse(MapExpansionState.collapsing.isVisible)
    }

    func testChromeAndTouchesOnlyOnTheStandingMap() {
        for state in MapExpansionState.allCases {
            let standing = state == .expanded
            XCTAssertEqual(state.showsChrome, standing, "хром у \(state)")
            XCTAssertEqual(state.isInteractive, standing, "пальцы у \(state)")
        }
    }

    /// Слот героя показывает снимок всегда, кроме покоя: карта в это время
    /// лежит в полноэкранном слое, и пустой прямоугольник на её месте — это
    /// моргание, которое видно глазом.
    func testHeroShowsSnapshotWheneverTheMapIsAway() {
        XCTAssertFalse(MapExpansionState.collapsed.heroShowsSnapshot)
        for state in MapExpansionState.allCases where state != .collapsed {
            XCTAssertTrue(state.heroShowsSnapshot, "снимок у \(state)")
        }
    }

    // MARK: - Времена

    func testChromeAppearsWithTheStableMap() {
        let delay = MapExpansionState.chromeDelay(reduceMotion: false)
        XCTAssertEqual(delay, 0)
        XCTAssertLessThan(delay, MapExpansionState.settleDelay(reduceMotion: false))
    }

    /// Reduce Motion: движения нет, значит и ждать нечего — хром приходит
    /// сразу, а кроссфейд короче пружины.
    func testReduceMotionCrossFadesWithoutWaiting() {
        XCTAssertEqual(MapExpansionState.chromeDelay(reduceMotion: true), 0)
        XCTAssertEqual(
            MapExpansionState.settleDelay(reduceMotion: true),
            MapExpansionState.reducedDuration)
        XCTAssertLessThan(
            MapExpansionState.reducedDuration, MapExpansionState.duration)
    }

}
