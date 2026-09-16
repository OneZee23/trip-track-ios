import XCTest
import MapKit
@testable import TripTrack

/// Карта поездки — ОДНА на экран.
///
/// Предмет проверки прямой: сколько раз за раскрытие и закрытие создаётся
/// `MKMapView`. До 0.7.0 их было две — герой и полноэкранная шторка, — и
/// вторая собиралась целиком (разрез маршрута по скорости, оверлеи, пины,
/// посадка вуали, первый растр тумана) ровно в ту секунду, когда человек
/// нажал «развернуть».
@MainActor
final class TripMapHostTests: XCTestCase {

    private var host: TripMapHost!

    override func setUp() {
        super.setUp()
        host = TripMapHost()
    }

    /// Поле обнуляется явно: XCTest держит экземпляры до конца прогона, и
    /// `MKMapView`, оставшаяся в живом тесте, роняет чужой класс (см.
    /// CLAUDE.md «Ловушки»).
    override func tearDown() {
        host?.tearDown()
        host = nil
        super.tearDown()
    }

    func testFirstAskBuildsTheMapExactlyOnce() {
        var built = 0
        _ = host.map(orMake: { built += 1; return MKMapView() })
        XCTAssertEqual(built, 1)
        XCTAssertEqual(host.creationCount, 1)
    }

    /// Герой → полный экран → герой: три запроса карты, одна карта.
    func testHeroAndFullscreenShareOneMapInstance() {
        var built = 0
        let make = { () -> MKMapView in built += 1; return MKMapView() }
        let hero = host.map(orMake: make)
        let fullscreen = host.map(orMake: make)
        let back = host.map(orMake: make)
        XCTAssertEqual(built, 1, "вторая MKMapView и есть вся поломка")
        XCTAssertEqual(host.creationCount, 1)
        XCTAssertTrue(hero === fullscreen)
        XCTAssertTrue(fullscreen === back)
    }

    /// Координатор общий по той же причине: он делегат карты и держит её
    /// память. Второй координатор на ту же карту — это вторая вуаль.
    func testCoordinatorIsSharedAndMarkedHosted() {
        var built = 0
        let make = { () -> RouteMapView.Coordinator in
            built += 1
            return RouteMapView.Coordinator(showsFog: false, rotatable: true)
        }
        let first = host.coordinator(orMake: make)
        let second = host.coordinator(orMake: make)
        XCTAssertEqual(built, 1)
        XCTAssertTrue(first === second)
        XCTAssertTrue(first.isHosted, "иначе dismantleUIView снимет вуаль на переезде")
    }

    /// `tearDown` — единственное место, где вуаль снимается с общей карты.
    /// После него хост пуст и следующий запрос строит карту заново.
    func testTearDownReleasesEverything() {
        var built = 0
        let make = { () -> MKMapView in built += 1; return MKMapView() }
        _ = host.map(orMake: make)
        let coordinator = host.coordinator(orMake: {
            RouteMapView.Coordinator(showsFog: false, rotatable: false)
        })
        host.tearDown()
        XCTAssertFalse(coordinator.isHosted)
        XCTAssertNil(host.mapView)
        XCTAssertNil(host.coordinator)
        _ = host.map(orMake: make)
        XCTAssertEqual(built, 2)
        XCTAssertEqual(host.creationCount, 2)
    }

    /// Снимок — для слота героя на время переезда. У карты без границ его
    /// нет вовсе: пустая картинка хуже честной подложки.
    func testSnapshotIsSkippedForAZeroSizedMap() {
        _ = host.map(orMake: { MKMapView() })
        host.captureSnapshot()
        XCTAssertNil(host.snapshot)
    }

    func testSnapshotIsTakenForASizedMapAndClearedOnDemand() {
        _ = host.map(orMake: {
            MKMapView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        })
        host.captureSnapshot()
        XCTAssertNotNil(host.snapshot)
        XCTAssertEqual(host.snapshot?.size, CGSize(width: 320, height: 200))
        host.clearSnapshot()
        XCTAssertNil(host.snapshot)
    }
}
