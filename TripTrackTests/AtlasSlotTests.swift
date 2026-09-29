import XCTest
@testable import TripTrack

/// Геометрия нижнего слота «Атласа» — по таблице спеки, а не по одному
/// телефону.
///
/// Доска S7 («Размеры экранов») даёт готовые числа для четырёх iPhone, и
/// таблица в спеке §9 — это ПРОВЕРКА формул, а не их источник. Здесь она
/// проверкой и работает: формула, подогнанная под один телефон, разъехалась бы с
/// остальными тремя молча.
final class AtlasSlotTests: XCTestCase {

    private let se = AtlasSlot(height: 667, safeTop: 20, safeBottom: 0)
    private let mini = AtlasSlot(height: 812, safeTop: 50, safeBottom: 34)
    /// 390 × 844 с зоной 47 — это iPhone 13/14, а не 15. Раньше здесь стояла
    /// зона 48 с подписью «iPhone 15»: такой зоны нет ни у одного телефона, у
    /// 13/14 она 47, у 13 mini 50, у 15/16 — 59. Поймано ревью дизайна 0.8.4.
    private let thirteen = AtlasSlot(height: 844, safeTop: 47, safeBottom: 34)
    /// Настоящий 15/16 — 393 × 852. В таблице его не было ни разу: формулы
    /// проверялись на геометрии, которой нет ни у одного телефона.
    private let fifteen = AtlasSlot(height: 852, safeTop: 59, safeBottom: 34)
    private let proMax = AtlasSlot(height: 932, safeTop: 59, safeBottom: 34)

    // MARK: Положения

    /// Числа эрраты 1: заголовок вкладки переехал в шторку первой строкой, и
    /// каждое содержимое выросло на эти 54 pt. Сводка 588 → 534, подсказка
    /// 700 → 654.
    func testDetentTopsMatchTheErrataTable() {
        XCTAssertEqual(thirteen.collapsedTop(), 534, "сводка на 13/14")
        XCTAssertEqual(thirteen.peekTop, 654, "подсказка на 13/14")
        XCTAssertEqual(thirteen.expandedTop, 103, "список на 13/14: зона 47 + 56")
        XCTAssertEqual(thirteen.collapsedTop(.region), 456, "регион на 13/14")
        XCTAssertEqual(thirteen.substateCeiling, 420, "потолок подсостояния")

        XCTAssertEqual(mini.collapsedTop(), 502, "сводка на 13 mini")
        XCTAssertEqual(mini.peekTop, 622, "подсказка на 13 mini")
        XCTAssertEqual(mini.expandedTop, 106, "список на 13 mini: зона 50 + 56")

        XCTAssertEqual(proMax.collapsedTop(), 622, "сводка на 15 Pro Max")
        XCTAssertEqual(proMax.peekTop, 742, "подсказка на 15 Pro Max")
        XCTAssertEqual(proMax.expandedTop, 115, "список на 15 Pro Max")
    }

    /// Ни одно подсостояние не поднимается выше потолка эрраты: там начинают
    /// гаснуть кнопки карты, а в подсостоянии они нужны.
    func testEverySubstateStaysUnderItsCeiling() {
        for (name, slot) in [("SE", se), ("13 mini", mini),
                             ("13/14", thirteen), ("15/16", fifteen), ("15 Pro Max", proMax)] {
            XCTAssertGreaterThanOrEqual(slot.collapsedTop(.region), slot.substateCeiling,
                                        "регион поднялся выше потолка: \(name)")
        }
    }

    /// На SE таблица спеки считает таб-бар на 10 pt от низа, а у нас
    /// `CustomTabBar.bottomGap` равен 22 всегда — решение 0.8.1, и таб-бар эта
    /// версия не меняет. Слот там ниже таблицы ровно на эти 12 pt.
    func testSEFollowsOurTabBarRatherThanTheTable() {
        XCTAssertEqual(se.expandedTop, 76, "список на SE — как в таблице")
        XCTAssertEqual(se.collapsedTop(), 577 - 220, "сводка на SE считается от нашего таб-бара")
        XCTAssertFalse(se.showsPeekRow, "под 700 pt строки подсказки нет вовсе")
        XCTAssertTrue(thirteen.showsPeekRow)
    }

    /// Высота свёрнутой шторки — ЧИСЛОМ на каждое содержимое, как записано в
    /// `tokens.json`. Меряется она иначе, и мерить её нам уже запрещено.
    func testCollapsedTopFollowsItsContent() {
        XCTAssertEqual(thirteen.collapsedTop(.summary), 534, "обычная сводка")
        XCTAssertEqual(thirteen.collapsedTop(.shortCard), 542, "пустые дни и ошибка")
        XCTAssertEqual(thirteen.collapsedTop(.emptyAtlas), 524, "пустой атлас")
        XCTAssertEqual(thirteen.collapsedTop(.withNoticeRow), 478, "запись и офлайн")
    }

    // MARK: Жест

    /// Порог 45 %, а не половина: открыть список легче, чем закрыть.
    func testSettleBoundarySitsAtFortyFivePercentOfThePath() {
        let boundary = thirteen.settleBoundary()
        XCTAssertEqual(boundary, 534 - (534 - thirteen.expandedTop) * 0.45, accuracy: 0.001)

        XCTAssertEqual(AtlasSlot.settle(top: boundary - 1, velocity: 0, slot: thirteen), .expanded)
        XCTAssertEqual(AtlasSlot.settle(top: boundary + 1, velocity: 0, slot: thirteen), .collapsed)
    }

    /// Бросок летит ПО НАПРАВЛЕНИЮ жеста, даже против ближайшего положения.
    func testAFlickBeatsTheNearestDetent() {
        XCTAssertEqual(AtlasSlot.settle(top: 520, velocity: -400, slot: thirteen), .expanded,
                       "бросок вверх у самой сводки раскрывает список")
        XCTAssertEqual(AtlasSlot.settle(top: 130, velocity: 400, slot: thirteen), .collapsed,
                       "бросок вниз у самого списка сворачивает")
        XCTAssertEqual(AtlasSlot.settle(top: 520, velocity: -299, slot: thirteen), .collapsed,
                       "299 pt/с — это ещё не бросок")
    }

    /// За границей — резинка с коэффициентом 0.3, и границы у неё разные:
    /// пока выбрано место, нижняя граница сама подсказка, иначе карточка
    /// подпрыгивала бы вверх от любого касания.
    func testRubberBandOutsideTheBounds() {
        XCTAssertEqual(thirteen.clamped(top: 300), 300, "внутри границ палец ведёт один к одному")
        XCTAssertEqual(thirteen.clamped(top: thirteen.expandedTop - 100),
                       thirteen.expandedTop - 30, accuracy: 0.001)
        XCTAssertEqual(thirteen.clamped(top: 534 + 100), 534 + 30, accuracy: 0.001)
        XCTAssertEqual(thirteen.clamped(top: 654, lowerBound: .peek), 654,
                       "в подсказке нижняя граница — она сама")
    }

    // MARK: Подпись Apple

    /// Подпись «Maps · Legal» обязана быть видна — прятать её нельзя, API
    /// для этого нет, а попытка рискует отказом на ревью (CLAUDE.md).
    ///
    /// Сторож держит ОБА края: подпись стоит ровно на 8 pt выше слота в
    /// сводке и в подсказке — и НЕ считается по списку. Инсет по списку был
    /// бы 748 pt на карте высотой 844, а MapKit кадрирует камеру по сумме
    /// полей разметки: на отрицательном остатке он отвечает кадром в пять раз
    /// шире запрошенного.
    func testAttributionSitsAboveTheSlotAndNeverFollowsTheList() {
        XCTAssertEqual(thirteen.attributionInset(.collapsed), 844 - 534 + 8)
        XCTAssertEqual(thirteen.attributionInset(.peek), 844 - 654 + 8)
        XCTAssertEqual(thirteen.attributionInset(.expanded), thirteen.attributionInset(.collapsed),
                       "по списку инсет не считается: он сломал бы кадрирование камеры")

        // Инвариант честный, а не «меньше половины экрана»: MapKit кадрирует
        // по остатку, и важно ровно то, что остаток живой.
        let minimumViewport: CGFloat = 120
        for (name, slot) in [("SE", se), ("13 mini", mini),
                             ("13/14", thirteen), ("15/16", fifteen), ("15 Pro Max", proMax)] {
            for detent in AtlasSheetDetent.allCases {
                for variant in [AtlasSummaryVariant.summary, .shortCard,
                                .emptyAtlas, .withNoticeRow, .region] {
                    let inset = slot.attributionInset(detent, variant: variant)
                    XCTAssertGreaterThan(inset, 0, "\(name) \(detent) \(variant)")
                    XCTAssertGreaterThan(slot.height - slot.safeTop - inset, minimumViewport,
                                         "у карты не осталось кадра: \(name) \(detent) \(variant)")
                }
            }
        }
    }

    /// Строка записи поднимает шторку — и подпись обязана подняться вместе с
    /// ней, иначе шторка накроет «Legal».
    func testAttributionFollowsATallerSummary() {
        XCTAssertEqual(thirteen.attributionInset(.collapsed, variant: .withNoticeRow), 844 - 478 + 8)
    }

    /// Подсостояние региона выше сводки, и подпись поднимается за ним — но
    /// карте обязан остаться живой кадр НА ВСЕХ ЧЕТЫРЁХ телефонах.
    ///
    /// Считается по тому же, по чему считает MapKit: высота минус зона
    /// сверху минус наш инсет. Ниже `minimumViewport` просить бессмысленно —
    /// на отрицательном остатке MapKit отвечает кадром во весь мир
    /// (CLAUDE.md, 0.8.1).
    func testRegionSubstateStillLeavesTheMapALiveViewport() {
        let minimumViewport: CGFloat = 120
        for (name, slot) in [("SE", se), ("13 mini", mini),
                             ("13/14", thirteen), ("15/16", fifteen), ("15 Pro Max", proMax)] {
            let inset = slot.attributionInset(.collapsed, variant: .region)
            XCTAssertEqual(inset, slot.height - slot.collapsedTop(.region) + 8, "\(name)")
            XCTAssertGreaterThan(slot.height - slot.safeTop - inset, minimumViewport,
                                 "у карты не осталось кадра: \(name)")
        }
        XCTAssertEqual(thirteen.collapsedTop(.region), 456, "верх региона из таблицы спеки")
    }

    // MARK: Жест подсостояния

    /// Вверх подсостояние идёт к списку — там его поездки; за списком
    /// резинка, как у сводки.
    func testSubstateDragGoesUpToTheListAndOneToOneDown() {
        XCTAssertEqual(thirteen.substateTop(dragged: 300, variant: .region), 300,
                       accuracy: 0.001, "между списком и своей высотой — один к одному")
        XCTAssertEqual(thirteen.substateTop(dragged: thirteen.expandedTop - 100,
                                            variant: .region), thirteen.expandedTop - 30,
                       accuracy: 0.001, "выше списка — резинка 0.3")
        XCTAssertEqual(thirteen.substateTop(dragged: 700, variant: .region), 700,
                       accuracy: 0.001, "ниже своей высоты палец ведёт один к одному: это закрытие")
    }

    /// Бросок вниз ИЗ СПИСКА сворачивает регион, а не закрывает его: закрытие
    /// начинается только ниже его собственной высоты.
    func testSubstateClosesOnlyWhenDraggedBelowItself() {
        let rest = thirteen.collapsedTop(.region)
        XCTAssertFalse(AtlasSlot.substateDismisses(top: 200, velocity: 800,
                                                   slot: thirteen, variant: .region),
                       "бросок вниз из списка — это «сверни», а не «закрой»")
        XCTAssertFalse(AtlasSlot.substateDismisses(top: rest + 40, velocity: 0,
                                                   slot: thirteen, variant: .region),
                       "сорок точек — ещё не закрытие")
        XCTAssertTrue(AtlasSlot.substateDismisses(top: rest + 80, velocity: 0,
                                                  slot: thirteen, variant: .region))
        XCTAssertTrue(AtlasSlot.substateDismisses(top: rest + 10, velocity: 400,
                                                  slot: thirteen, variant: .region),
                      "брошенное вниз закрывается и с малого смещения")
        XCTAssertFalse(AtlasSlot.substateDismisses(top: rest + 80, velocity: -400,
                                                   slot: thirteen, variant: .region),
                       "бросок ВВЕРХ не закрывает ничего")
    }

    // MARK: Затухание

    /// Рампы заголовка больше нет: он закреплён внутри шторки и не гаснет
    /// (эррата 1). Осталась одна — у кнопок карты и подписи Apple.
    func testOnlyTheMapControlsStillFade() {
        XCTAssertEqual(AtlasSlot.controlsOpacity(slotTop: 534), 1)
        XCTAssertEqual(AtlasSlot.controlsOpacity(slotTop: 300), 1)
        XCTAssertEqual(AtlasSlot.controlsOpacity(slotTop: 270), 0.5, accuracy: 0.001)
        XCTAssertEqual(AtlasSlot.controlsOpacity(slotTop: 240), 0)
    }
}
