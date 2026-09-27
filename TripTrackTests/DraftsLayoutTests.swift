import XCTest
@testable import TripTrack

/// Геометрия «Черновиков» — по таблице спеки §8, а не под один телефон.
final class DraftsLayoutTests: XCTestCase {

    private let se = DraftsLayout(height: 667, safeTop: 20, safeBottom: 0)
    private let mini = DraftsLayout(height: 812, safeTop: 50, safeBottom: 34)
    private let fifteen = DraftsLayout(height: 844, safeTop: 48, safeBottom: 34)
    private let sixteen = DraftsLayout(height: 852, safeTop: 59, safeBottom: 34)
    private let proMax = DraftsLayout(height: 932, safeTop: 59, safeBottom: 34)

    func testHeaderAndButtonMatchTheSpecTable() {
        XCTAssertEqual(fifteen.headerBottom, 94)
        XCTAssertEqual(fifteen.buttonTop, 690)
        XCTAssertEqual(fifteen.dialogTop, 302)

        XCTAssertEqual(mini.headerBottom, 96)
        XCTAssertEqual(mini.buttonTop, 658)
        XCTAssertEqual(mini.dialogTop, 286)

        XCTAssertEqual(sixteen.headerBottom, 105)
        XCTAssertEqual(sixteen.buttonTop, 698)
        XCTAssertEqual(sixteen.dialogTop, 306)

        XCTAssertEqual(proMax.headerBottom, 105)
        XCTAssertEqual(proMax.buttonTop, 778)
        XCTAssertEqual(proMax.dialogTop, 346)
    }

    /// На SE таблица спеки считает таб-бар на 10 pt от низа, у нас он всегда
    /// на 22 (решение 0.8.1, таб-бар эта переделка не трогает). Верхние числа
    /// совпадают с таблицей точно, нижние ровно на 12 pt ниже.
    func testSEMatchesAboveAndIsTwelveBelowUnderneath() {
        XCTAssertEqual(se.headerBottom, 66, "шапка считается от зоны — совпадает")
        XCTAssertEqual(se.dialogTop, 213.5, accuracy: 0.51, "диалог от середины — совпадает")
        XCTAssertEqual(se.buttonTop, 525 - 12, "кнопка ниже таблицы на поле таб-бара")
        XCTAssertEqual(se.listBottomInset, 154 + 12)
    }

    /// Отступ содержимого один на всех телефонах с индикатором: он собран из
    /// высот, а не из размера экрана.
    func testListInsetIsTheSameEverywhere() {
        for layout in [mini, fifteen, sixteen, proMax] {
            XCTAssertEqual(layout.listBottomInset, 166)
        }
    }

    /// Две кнопки режима выбора закрывают ровно ту же строку, что одна
    /// кнопка обычного вида: 16 + 40 % + 8 + остаток + 16.
    func testSelectionButtonsCoverTheSameRowAsTheSingleOne() {
        for (name, layout) in [("iPhone 15", DraftsLayout(height: 844, safeTop: 48,
                                                          safeBottom: 34, width: 390)),
                               ("SE", DraftsLayout(height: 667, safeTop: 20,
                                                   safeBottom: 0, width: 375))] {
            let row = layout.width - 32
            XCTAssertEqual(layout.deleteButtonWidth, row * 0.4, accuracy: 0.01, name)
            XCTAssertLessThan(layout.deleteButtonWidth + 8, row,
                              "«Мои · N» не осталось места: \(name)")
        }
    }

    /// Пустая плашка стоит долей экрана, а не отступом от шапки: на SE
    /// отступ увёл бы её к середине.
    func testEmptyStateSitsAtTheSameOpticalHeightEverywhere() {
        XCTAssertEqual(fifteen.emptyTop, 253.2, accuracy: 0.1, "доска DR-10 — около 259")
        for (name, layout) in [("SE", se), ("13 mini", mini), ("iPhone 16", sixteen),
                               ("15 Pro Max", proMax)] {
            XCTAssertGreaterThan(layout.emptyTop, layout.headerBottom + 40,
                                 "плашка легла на шапку: \(name)")
            XCTAssertLessThan(layout.emptyTop, layout.height / 2,
                              "плашка уехала ниже середины: \(name)")
        }
    }

    /// Кнопка НИКОГДА не наезжает на таб-бар и не уходит под шапку: между
    /// ними обязано остаться место под список.
    func testTheButtonAlwaysSitsBetweenTheHeaderAndTheTabBar() {
        for (name, layout) in [("SE", se), ("13 mini", mini), ("iPhone 15", fifteen),
                               ("iPhone 16", sixteen), ("15 Pro Max", proMax)] {
            XCTAssertLessThan(layout.buttonTop + 52, layout.tabBarTop, "кнопка легла на таб-бар: \(name)")
            XCTAssertGreaterThan(layout.buttonTop, layout.headerBottom + 100,
                                 "кнопке не осталось места под списком: \(name)")
        }
    }
}
