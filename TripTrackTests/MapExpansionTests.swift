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

    /// `expanding` и `collapsing` — это кадр В РАМКЕ ГЕРОЯ: пружине нужно от
    /// чего оттолкнуться, иначе карта возникает на весь экран сразу.
    func testOnlyExpandedFillsTheScreen() {
        XCTAssertFalse(MapExpansionState.collapsed.fillsScreen)
        XCTAssertFalse(MapExpansionState.expanding.fillsScreen)
        XCTAssertTrue(MapExpansionState.expanded.fillsScreen)
        XCTAssertFalse(MapExpansionState.collapsing.fillsScreen)
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

    func testChromeArrivesAfterSixtyPercentOfTheSpring() {
        let delay = MapExpansionState.chromeDelay(reduceMotion: false)
        XCTAssertEqual(delay, MapExpansionState.response * 0.6, accuracy: 0.0001)
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
            MapExpansionState.reducedDuration, MapExpansionState.response)
    }

    func testMountDelayIsShorterThanTheSpringItPrecedes() {
        XCTAssertGreaterThan(MapExpansionState.mountDelay, 0)
        XCTAssertLessThan(MapExpansionState.mountDelay, MapExpansionState.response)
    }

    func testSpringConstantsAreTheOnesTheOwnerApproved() {
        XCTAssertEqual(MapExpansionState.response, 0.38, accuracy: 0.0001)
        XCTAssertEqual(MapExpansionState.dampingFraction, 0.9, accuracy: 0.0001)
    }
}
