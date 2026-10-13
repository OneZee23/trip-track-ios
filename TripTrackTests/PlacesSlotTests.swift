import XCTest
@testable import TripTrack

/// Геометрия панели «Мест» — по таблице спеки §9, а не под один телефон.
///
/// Таблица там ПРОВЕРКА формул, а не их источник: формула, подогнанная под
/// один телефон, разъехалась бы с остальными четырьмя молча. Ровно этим тестом
/// «Атлас» и ловил свои расхождения.
final class PlacesSlotTests: XCTestCase {

    private let se = PlacesSlot(height: 667, safeTop: 20, safeBottom: 0)
    private let mini = PlacesSlot(height: 812, safeTop: 50, safeBottom: 34)
    /// 390 × 844 с зоной 47 — это iPhone 13/14. Стояла зона 48 с подписью
    /// «iPhone 15»: такой зоны нет ни у одного телефона (13/14 — 47, mini — 50,
    /// 15/16 — 59). Тот же дефект жил в AtlasSlotTests и DraftsLayoutTests.
    private let thirteen = PlacesSlot(height: 844, safeTop: 47, safeBottom: 34)
    private let sixteen = PlacesSlot(height: 852, safeTop: 59, safeBottom: 34)
    private let proMax = PlacesSlot(height: 932, safeTop: 59, safeBottom: 34)

    // MARK: Таблица

    func testStopsMatchTheSpecTable() {
        XCTAssertEqual(thirteen.top(of: .map), 654)
        XCTAssertEqual(thirteen.top(of: .selectedPlace), 590)
        XCTAssertEqual(thirteen.top(of: .selectedHint), 522)
        XCTAssertEqual(thirteen.top(of: .half), 380)
        XCTAssertEqual(thirteen.top(of: .empty), 280)
        XCTAssertEqual(thirteen.top(of: .list), 103, "зона 47 + 56")

        XCTAssertEqual(mini.top(of: .map), 622)
        XCTAssertEqual(mini.top(of: .half), 348)
        XCTAssertEqual(mini.top(of: .list), 106)
        XCTAssertEqual(mini.top(of: .empty), 248)

        XCTAssertEqual(sixteen.top(of: .map), 662)
        XCTAssertEqual(sixteen.top(of: .half), 388)
        XCTAssertEqual(sixteen.top(of: .list), 115)
        XCTAssertEqual(sixteen.top(of: .empty), 288)

        XCTAssertEqual(proMax.top(of: .map), 742)
        XCTAssertEqual(proMax.top(of: .half), 468)
        XCTAssertEqual(proMax.top(of: .list), 115)
        XCTAssertEqual(proMax.top(of: .empty), 368)
    }

    /// На SE таблица спеки считает таб-бар на 10 pt от низа, а у нас
    /// `CustomTabBar.bottomGap` равен 22 всегда — решение 0.8.1, и таб-бар
    /// эта переделка не трогает. Все нижние положения там ровно на 12 pt
    /// ниже таблицы, и это записанное расхождение, а не промах.
    func testSEIsTwelvePointsBelowTheTableAndHasNoHalf() {
        XCTAssertEqual(se.top(of: .map), 489 - 12)
        XCTAssertEqual(se.top(of: .empty), 115 - 12)
        XCTAssertEqual(se.placeSheetTop, 289 - 12)
        XCTAssertEqual(se.top(of: .list), 76, "верхнее положение от зоны, а не от таб-бара")

        XCTAssertFalse(se.showsHalf, "на SE половины нет")
        XCTAssertEqual(se.defaultStop, .list, "SE открывается списком")
        XCTAssertEqual(se.reachableStops, [.list, .map])
        for slot in [mini, thirteen, sixteen, proMax] {
            XCTAssertTrue(slot.showsHalf)
            XCTAssertEqual(slot.defaultStop, .half)
        }
    }

    /// Список НИКОГДА не поднимается выше безопасной зоны: под часами не
    /// оказывается ни ручка, ни заголовок. Это та самая поломка, которую мы
    /// чинили на «Атласе» 27 сентября.
    func testTheListNeverSlidesUnderTheStatusBar() {
        for (name, slot) in [("SE", se), ("13 mini", mini), ("13/14", thirteen), ("15/16", sixteen),
                             ("iPhone 16", sixteen), ("15 Pro Max", proMax)] {
            XCTAssertGreaterThanOrEqual(slot.top(of: .list), slot.safeTop,
                                        "список ушёл под статус-бар: \(name)")
            XCTAssertEqual(slot.top(of: .list) - slot.safeTop, 56, "\(name)")
        }
    }

    // MARK: Жест

    func testSettleBoundariesSitAtFortyFivePercent() {
        let map = thirteen.top(of: .map), half = thirteen.top(of: .half)
        let list = thirteen.top(of: .list)
        let upper = SlotGesture.boundary(from: map, to: half)
        let lower = SlotGesture.boundary(from: half, to: list)

        XCTAssertEqual(thirteen.settle(top: upper + 1, velocity: 0, from: .half), .map)
        XCTAssertEqual(thirteen.settle(top: upper - 1, velocity: 0, from: .map), .half)
        XCTAssertEqual(thirteen.settle(top: lower + 1, velocity: 0, from: .list), .half)
        XCTAssertEqual(thirteen.settle(top: lower - 1, velocity: 0, from: .half), .list)
    }

    /// Бросок летит к СОСЕДНЕМУ положению по направлению жеста, даже против
    /// ближайшего, — и ровно на один шаг, а не через всю шкалу.
    func testAFlickMovesExactlyOneStop() {
        XCTAssertEqual(thirteen.settle(top: 640, velocity: -400, from: .map), .half,
                       "бросок вверх от карты — половина, а не список")
        XCTAssertEqual(thirteen.settle(top: 370, velocity: -400, from: .half), .list)
        XCTAssertEqual(thirteen.settle(top: 120, velocity: 400, from: .list), .half)
        XCTAssertEqual(thirteen.settle(top: 640, velocity: -299, from: .map), .map,
                       "299 pt/с — это ещё не бросок")
    }

    /// На SE половины нет, и бросок от карты обязан вести сразу в список.
    func testOnSEAFlickSkipsTheMissingHalf() {
        XCTAssertEqual(se.settle(top: 470, velocity: -400, from: .map), .list)
        XCTAssertEqual(se.settle(top: 90, velocity: 400, from: .list), .map)
        let boundary = SlotGesture.boundary(from: se.top(of: .map), to: se.top(of: .list))
        XCTAssertEqual(se.settle(top: boundary + 1, velocity: 0, from: .list), .map)
        XCTAssertEqual(se.settle(top: boundary - 1, velocity: 0, from: .map), .list)
    }

    func testRubberBandOutsideTheBounds() {
        XCTAssertEqual(thirteen.clamped(300), 300, "внутри границ палец ведёт один к одному")
        XCTAssertEqual(thirteen.clamped(thirteen.top(of: .list) - 100),
                       thirteen.top(of: .list) - 30, accuracy: 0.001)
        XCTAssertEqual(thirteen.clamped(654 + 100), 654 + 30, accuracy: 0.001)
    }

    // MARK: Поля карты

    /// Инсет карты не считается по СПИСКУ никогда: MapKit кадрирует камеру по
    /// сумме полей разметки, и на списке остаток ушёл бы в минус — кадр во
    /// весь мир (CLAUDE.md, 0.8.1).
    func testMapInsetNeverFollowsTheList() {
        XCTAssertEqual(thirteen.mapBottomInset(.list), thirteen.mapBottomInset(.half))

        // Живой кадр обязан остаться ВЕЗДЕ, ОТКУДА КАМЕРУ ПРОСЯТ КАДРИРОВАТЬ.
        // Пустая вкладка в этот список не входит: на ней нет ни булавок, ни
        // команд камере, а панель там по спеке занимает почти весь экран (на
        // SE карте остаётся 83 pt). Требовать от неё кадра значило бы
        // выдумывать требование ради круглого числа.
        let minimumViewport: CGFloat = 120
        let framing: [PlacesPanelStop] = [.map, .selectedPlace, .selectedHint, .half, .list]
        for (name, slot) in [("SE", se), ("13 mini", mini), ("13/14", thirteen), ("15/16", sixteen),
                             ("iPhone 16", sixteen), ("15 Pro Max", proMax)] {
            for stop in PlacesPanelStop.allCases {
                XCTAssertGreaterThan(slot.mapBottomInset(stop), 0, "\(name) \(stop)")
            }
            for stop in framing {
                let inset = slot.mapBottomInset(stop)
                XCTAssertGreaterThan(slot.height - slot.safeTop - inset, minimumViewport,
                                     "у карты не осталось кадра: \(name) \(stop)")
            }
        }
    }
}
