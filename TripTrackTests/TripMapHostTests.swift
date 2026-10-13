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

    // MARK: - Кто держит карту

    /// На push чужой поездки прежняя и новая ветки SwiftUI могут жить
    /// одновременно. Раньше каждый layout забирал карту назад, вызывая
    /// бесконечный UIKit layout при первом открытии поездки из ленты.
    func testPreviousSlotCannotReclaimMapDuringOverlappingLayouts() {
        let map = host.map(orMake: { MKMapView() })
        let previous = TripMapSlotView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let current = TripMapSlotView(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        previous.adopt(map)

        // Запрос хоста сохраняет прежнее гнездо до явной передачи.
        let handedOver = host.map(orMake: { XCTFail("created a second map"); return MKMapView() })
        XCTAssertTrue(map.superview === previous)
        current.adopt(handedOver)
        XCTAssertNil(previous.map, "старый адаптер больше не вправе обновлять эту карту")

        for _ in 0..<4 {
            previous.layoutSubviews()
            XCTAssertTrue(map.superview === current, "layout прежнего слота не переносит карту")
            current.layoutSubviews()
            XCTAssertTrue(map.superview === current)
            XCTAssertEqual(map.frame, current.bounds)
        }
        XCTAssertEqual(host.creationCount, 1)
    }

    /// Возврат с полного экрана — новая явная передача той же карты.
    func testExplicitTransferBackToHeroRevokesFullscreenSlot() {
        let map = host.map(orMake: { MKMapView() })
        let hero = TripMapSlotView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let fullscreen = TripMapSlotView(frame: CGRect(x: 0, y: 0, width: 320, height: 700))
        var heroFits = 0
        hero.onResize = { heroFits += 1 }
        hero.adopt(map)
        fullscreen.adopt(map)
        hero.adopt(map)

        fullscreen.layoutSubviews()
        hero.layoutSubviews()
        XCTAssertNil(fullscreen.map)
        XCTAssertTrue(map.superview === hero)
        XCTAssertEqual(map.frame, hero.bounds)
        XCTAssertEqual(heroFits, 2, "возврат требует fit даже в прежний размер героя")
        XCTAssertEqual(host.creationCount, 1)
    }

    func testReusedHeroCanClaimMapButStaleFullscreenCannot() {
        let map = host.map(orMake: { MKMapView() })
        let hero = TripMapSlotView()
        let fullscreen = TripMapSlotView()
        host.register(hero, for: .hero)
        host.register(fullscreen, for: .fullscreen)
        hero.adopt(map)
        host.activePresentation = .fullscreen
        XCTAssertFalse(host.canClaim(hero, for: .hero))
        XCTAssertTrue(host.canClaim(fullscreen, for: .fullscreen))
        fullscreen.adopt(map)
        XCTAssertNil(hero.map)

        host.activePresentation = .hero
        XCTAssertTrue(host.canClaim(hero, for: .hero))
        XCTAssertFalse(host.canClaim(fullscreen, for: .fullscreen))
        hero.adopt(map)
        XCTAssertTrue(map.superview === hero)
    }

    func testReplacementHeroInvalidatesOldSameRoleSlotAndItsLateDismantle() {
        let old = TripMapSlotView()
        let replacement = TripMapSlotView()
        host.register(old, for: .hero)
        host.register(replacement, for: .hero)
        XCTAssertFalse(host.canClaim(old, for: .hero))
        XCTAssertTrue(host.canClaim(replacement, for: .hero))
        host.unregister(old)
        XCTAssertTrue(host.canClaim(replacement, for: .hero))
    }

    /// A matching frame is insufficient: route fitting still needs the
    /// destination's first usable size, and a zero-size slot is not ready.
    func testSlotReportsFirstUsableSizeEvenWhenMapFrameAlreadyMatches() {
        let map = host.map(orMake: { MKMapView() })
        let slot = TripMapSlotView()
        var sizes: [CGSize] = []
        slot.onResize = { sizes.append(slot.bounds.size) }
        defer { slot.onResize = nil }
        slot.adopt(map)
        slot.bounds.size = CGSize(width: 320, height: 200)
        map.frame = slot.bounds
        slot.layoutSubviews()
        slot.layoutSubviews()
        XCTAssertEqual(sizes, [CGSize(width: 320, height: 200)],
                       "fit waits for usable bounds and runs once even when the frame matches")
    }

    /// SwiftUI creates the fullscreen slot before assigning its bounds.
    /// Reparenting must not collapse the live map or grow it to old + new size
    /// through an autoresizing mask before layout corrects that frame again.
    func testZeroSizeDestinationPreservesViewportUntilItsFirstLayout() {
        let map = host.map(orMake: { MKMapView() })
        let hero = TripMapSlotView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let fullscreen = TripMapSlotView()
        hero.adopt(map)
        var sizes: [CGSize] = []
        fullscreen.onResize = { sizes.append(map.bounds.size) }
        defer { fullscreen.onResize = nil }

        fullscreen.adopt(map)
        fullscreen.layoutSubviews()
        XCTAssertNil(hero.map)
        XCTAssertTrue(map.superview === fullscreen)
        XCTAssertEqual(map.frame, hero.bounds, "ownership changes before viewport size")
        XCTAssertTrue(sizes.isEmpty, "zero-sized destinations cannot fit a route")

        fullscreen.bounds.size = CGSize(width: 440, height: 956)
        XCTAssertEqual(map.bounds.size, hero.bounds.size,
                       "autoresizing must not add the new slot size to the retained viewport")
        fullscreen.layoutSubviews()
        fullscreen.layoutSubviews()
        XCTAssertEqual(map.frame, fullscreen.bounds)
        XCTAssertEqual(sizes, [CGSize(width: 440, height: 956)])
        XCTAssertEqual(host.creationCount, 1)
    }

    func testTransientEmptyLayoutDoesNotCollapseAnOwnedMap() {
        let map = host.map(orMake: { MKMapView() })
        let slot = TripMapSlotView(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        slot.adopt(map)
        let previousFrame = map.frame
        var resizes = 0
        slot.onResize = { resizes += 1 }
        defer { slot.onResize = nil }

        slot.bounds.size = .zero
        slot.layoutSubviews()
        XCTAssertEqual(map.frame, previousFrame)
        XCTAssertEqual(resizes, 0)

        slot.bounds.size = CGSize(width: 320, height: 200)
        slot.layoutSubviews()
        XCTAssertEqual(map.frame, slot.bounds)
        XCTAssertEqual(resizes, 1)
    }

    /// Пуш чужого экрана поверх поездки НЕ разбирает карту.
    ///
    /// `.onDisappear` в `NavigationStack` приходит и на накрытый экран —
    /// паспорт машины, чужой профиль, путешествие, экран места. Рвать карту
    /// на нём значило бы построить при возврате ВТОРУЮ `MKMapView` со второй
    /// вуалью: `makeUIView` полноэкранного слоя увидел бы пустой хост.
    func testPushAndPopKeepsOneMapCreation() async {
        var built = 0
        let make = { () -> MKMapView in built += 1; return MKMapView() }
        // Экран поездки смонтирован: одно представление — герой.
        let hero = host.map(orMake: make)
        host.retain()
        XCTAssertEqual(host.mounted, 1)

        // Пуш паспорта машины. Представление героя живо, снимать нечего.
        await settle()
        XCTAssertNotNil(host.mapView, "пуш не имеет права разбирать карту")

        // Возврат и раскрытие на полный экран: та же карта, тот же счёт.
        let fullscreen = host.map(orMake: make)
        host.retain()
        host.release()          // слот героя отдал карту слою
        await settle()
        XCTAssertTrue(hero === fullscreen)
        XCTAssertEqual(built, 1, "вторая MKMapView и есть вся поломка")
        XCTAssertEqual(host.creationCount, 1)
        XCTAssertNotNil(host.mapView)
    }

    /// Переезд между слотом героя и полноэкранным слоем — это «сняли одно,
    /// поставили другое», и порядок этих двух вызовов SwiftUI не обещает.
    /// Разрыв отложен на следующий виток, поэтому ноль между ними не считается.
    func testReparentDoesNotTearDown() async {
        _ = host.map(orMake: { MKMapView() })
        host.retain()
        host.release()          // герой снят ПЕРВЫМ
        host.retain()           // слой встал следом
        await settle()
        XCTAssertEqual(host.mounted, 1)
        XCTAssertNotNil(host.mapView, "переезд не имеет права снимать вуаль")
    }

    /// А вот уход экрана — настоящий: последнее представление снято, и на
    /// следующем витке карта отдаётся вместе с вуалью.
    func testLastReleaseTearsDown() async {
        _ = host.map(orMake: { MKMapView() })
        let coordinator = host.coordinator(orMake: {
            RouteMapView.Coordinator(showsFog: false, rotatable: false)
        })
        host.retain()
        host.release()
        await settle()
        XCTAssertEqual(host.mounted, 0)
        XCTAssertNil(host.mapView)
        XCTAssertNil(host.coordinator)
        XCTAssertFalse(coordinator.isHosted)
    }

    /// Дать отложенному разрыву дойти до главного актёра.
    private func settle() async {
        for _ in 0..<4 { await Task.yield() }
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
