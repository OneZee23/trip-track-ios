import XCTest
@testable import TripTrack

/// Геометрия нижнего слота «Атласа» — по таблице спеки, а не по одному
/// телефону.
///
/// Доска S7 («Размеры экранов») даёт готовые числа для четырёх iPhone, и
/// таблица в спеке §9 — это ПРОВЕРКА формул, а не их источник. Здесь она
/// проверкой и работает: формула, подогнанная под iPhone 15, разъехалась бы с
/// остальными тремя молча.
final class AtlasSlotTests: XCTestCase {

    private let se = AtlasSlot(height: 667, safeTop: 20, safeBottom: 0)
    private let mini = AtlasSlot(height: 812, safeTop: 48, safeBottom: 34)
    private let fifteen = AtlasSlot(height: 844, safeTop: 48, safeBottom: 34)
    private let proMax = AtlasSlot(height: 932, safeTop: 59, safeBottom: 34)

    // MARK: Положения

    func testDetentTopsMatchTheSpecTable() {
        XCTAssertEqual(fifteen.collapsedTop(), 588, "сводка на iPhone 15")
        XCTAssertEqual(fifteen.peekTop, 700, "подсказка на iPhone 15")
        XCTAssertEqual(fifteen.expandedTop, 104, "список на iPhone 15")

        XCTAssertEqual(mini.collapsedTop(), 556, "сводка на 13 mini")
        XCTAssertEqual(mini.peekTop, 668, "подсказка на 13 mini")
        XCTAssertEqual(mini.expandedTop, 104, "список на 13 mini")

        XCTAssertEqual(proMax.collapsedTop(), 676, "сводка на 15 Pro Max")
        XCTAssertEqual(proMax.peekTop, 788, "подсказка на 15 Pro Max")
        XCTAssertEqual(proMax.expandedTop, 115, "список на 15 Pro Max")
    }

    /// На SE таблица спеки считает таб-бар на 10 pt от низа, а у нас
    /// `CustomTabBar.bottomGap` равен 22 всегда — решение 0.8.1, и таб-бар эта
    /// версия не меняет. Слот там ниже таблицы ровно на эти 12 pt.
    func testSEFollowsOurTabBarRatherThanTheTable() {
        XCTAssertEqual(se.expandedTop, 76, "список на SE — как в таблице")
        XCTAssertEqual(se.collapsedTop(), 423 - 12, "сводка на SE ниже таблицы на поле таб-бара")
        XCTAssertFalse(se.showsPeekRow, "под 700 pt строки подсказки нет вовсе")
        XCTAssertTrue(fifteen.showsPeekRow)
    }

    /// Высота свёрнутой шторки — ЧИСЛОМ на каждое содержимое, как записано в
    /// `tokens.json`. Меряется она иначе, и мерить её нам уже запрещено.
    func testCollapsedTopFollowsItsContent() {
        XCTAssertEqual(fifteen.collapsedTop(.summary), 588, "обычная сводка")
        XCTAssertEqual(fifteen.collapsedTop(.shortCard), 596, "пустые дни и ошибка")
        XCTAssertEqual(fifteen.collapsedTop(.emptyAtlas), 578, "пустой атлас")
        XCTAssertEqual(fifteen.collapsedTop(.withNoticeRow), 532, "запись и офлайн")
    }

    // MARK: Жест

    /// Порог 45 %, а не половина: открыть список легче, чем закрыть.
    func testSettleBoundarySitsAtFortyFivePercentOfThePath() {
        let boundary = fifteen.settleBoundary()
        XCTAssertEqual(boundary, 588 - (588 - 104) * 0.45, accuracy: 0.001)

        XCTAssertEqual(AtlasSlot.settle(top: boundary - 1, velocity: 0, slot: fifteen), .expanded)
        XCTAssertEqual(AtlasSlot.settle(top: boundary + 1, velocity: 0, slot: fifteen), .collapsed)
    }

    /// Бросок летит ПО НАПРАВЛЕНИЮ жеста, даже против ближайшего положения.
    func testAFlickBeatsTheNearestDetent() {
        XCTAssertEqual(AtlasSlot.settle(top: 560, velocity: -400, slot: fifteen), .expanded,
                       "бросок вверх у самой сводки раскрывает список")
        XCTAssertEqual(AtlasSlot.settle(top: 130, velocity: 400, slot: fifteen), .collapsed,
                       "бросок вниз у самого списка сворачивает")
        XCTAssertEqual(AtlasSlot.settle(top: 560, velocity: -299, slot: fifteen), .collapsed,
                       "299 pt/с — это ещё не бросок")
    }

    /// За границей — резинка с коэффициентом 0.3, и границы у неё разные:
    /// пока выбрано место, нижняя граница сама подсказка, иначе карточка
    /// подпрыгивала бы вверх от любого касания.
    func testRubberBandOutsideTheBounds() {
        XCTAssertEqual(fifteen.clamped(top: 300), 300, "внутри границ палец ведёт один к одному")
        XCTAssertEqual(fifteen.clamped(top: 104 - 100), 104 - 30, accuracy: 0.001)
        XCTAssertEqual(fifteen.clamped(top: 588 + 100), 588 + 30, accuracy: 0.001)
        XCTAssertEqual(fifteen.clamped(top: 700, lowerBound: .peek), 700,
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
        XCTAssertEqual(fifteen.attributionInset(.collapsed), 844 - 588 + 8)
        XCTAssertEqual(fifteen.attributionInset(.peek), 844 - 700 + 8)
        XCTAssertEqual(fifteen.attributionInset(.expanded), fifteen.attributionInset(.collapsed),
                       "по списку инсет не считается: он сломал бы кадрирование камеры")

        for detent in AtlasSheetDetent.allCases {
            let inset = fifteen.attributionInset(detent)
            XCTAssertLessThan(inset, fifteen.height / 2,
                              "инсет больше половины карты ломает кадрирование MapKit")
            XCTAssertGreaterThan(inset, 0)
        }
    }

    /// Строка записи поднимает шторку — и подпись обязана подняться вместе с
    /// ней, иначе шторка накроет «Legal».
    func testAttributionFollowsATallerSummary() {
        XCTAssertEqual(fifteen.attributionInset(.collapsed, variant: .withNoticeRow), 844 - 532 + 8)
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
                             ("iPhone 15", fifteen), ("15 Pro Max", proMax)] {
            let inset = slot.attributionInset(.collapsed, variant: .region)
            XCTAssertEqual(inset, slot.height - slot.collapsedTop(.region) + 8, "\(name)")
            XCTAssertGreaterThan(slot.height - slot.safeTop - inset, minimumViewport,
                                 "у карты не осталось кадра: \(name)")
        }
        XCTAssertEqual(fifteen.collapsedTop(.region), 456, "верх региона из таблицы спеки")
    }

    // MARK: Жест подсостояния

    /// Вверх подсостояние идёт к списку — там его поездки; за списком
    /// резинка, как у сводки.
    func testSubstateDragGoesUpToTheListAndOneToOneDown() {
        XCTAssertEqual(fifteen.substateTop(dragged: 300, variant: .region), 300,
                       accuracy: 0.001, "между списком и своей высотой — один к одному")
        XCTAssertEqual(fifteen.substateTop(dragged: 104 - 100, variant: .region), 104 - 30,
                       accuracy: 0.001, "выше списка — резинка 0.3")
        XCTAssertEqual(fifteen.substateTop(dragged: 700, variant: .region), 700,
                       accuracy: 0.001, "ниже своей высоты палец ведёт один к одному: это закрытие")
    }

    /// Бросок вниз ИЗ СПИСКА сворачивает регион, а не закрывает его: закрытие
    /// начинается только ниже его собственной высоты.
    func testSubstateClosesOnlyWhenDraggedBelowItself() {
        let rest = fifteen.collapsedTop(.region)
        XCTAssertFalse(AtlasSlot.substateDismisses(top: 200, velocity: 800,
                                                   slot: fifteen, variant: .region),
                       "бросок вниз из списка — это «сверни», а не «закрой»")
        XCTAssertFalse(AtlasSlot.substateDismisses(top: rest + 40, velocity: 0,
                                                   slot: fifteen, variant: .region),
                       "сорок точек — ещё не закрытие")
        XCTAssertTrue(AtlasSlot.substateDismisses(top: rest + 80, velocity: 0,
                                                  slot: fifteen, variant: .region))
        XCTAssertTrue(AtlasSlot.substateDismisses(top: rest + 10, velocity: 400,
                                                  slot: fifteen, variant: .region),
                      "брошенное вниз закрывается и с малого смещения")
        XCTAssertFalse(AtlasSlot.substateDismisses(top: rest + 80, velocity: -400,
                                                   slot: fifteen, variant: .region),
                       "бросок ВВЕРХ не закрывает ничего")
    }

    // MARK: Затухание

    func testHeaderAndControlsFadeOnTheirOwnRamps() {
        XCTAssertEqual(AtlasSlot.headerOpacity(sheetTop: 588), 1)
        XCTAssertEqual(AtlasSlot.headerOpacity(sheetTop: 420), 1)
        XCTAssertEqual(AtlasSlot.headerOpacity(sheetTop: 350), 0.5, accuracy: 0.001)
        XCTAssertEqual(AtlasSlot.headerOpacity(sheetTop: 280), 0)
        XCTAssertEqual(AtlasSlot.headerOpacity(sheetTop: 104), 0)

        XCTAssertEqual(AtlasSlot.controlsOpacity(slotTop: 588), 1)
        XCTAssertEqual(AtlasSlot.controlsOpacity(slotTop: 300), 1)
        XCTAssertEqual(AtlasSlot.controlsOpacity(slotTop: 270), 0.5, accuracy: 0.001)
        XCTAssertEqual(AtlasSlot.controlsOpacity(slotTop: 240), 0)
    }

    /// Кадр 5 доски: шторка на 380, заголовок примерно на 0.7.
    func testTheDeveloperFrameAtThreeEighty() {
        XCTAssertEqual(AtlasSlot.headerOpacity(sheetTop: 380), 0.714, accuracy: 0.01)
        XCTAssertEqual(AtlasSlot.controlsOpacity(slotTop: 380), 1, "кнопки карты там ещё целы")
    }
}
