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
