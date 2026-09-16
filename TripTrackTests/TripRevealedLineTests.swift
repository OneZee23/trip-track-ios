import XCTest
@testable import TripTrack

/// Строка блока «Открыто» на экране итогов (0.7.0).
///
/// Проверяется тестом, а не глазами на телефоне, по одной причине: поездка, на
/// которой нашлись СРАЗУ секрет, загадка и веха, случается раз в месяцы, а
/// сломать порядок или потерять нулевую часть можно любой правкой.
final class TripRevealedLineTests: XCTestCase {

    private let sep = "\u{00A0}· "

    // MARK: Состав

    func testAllPartsGoInOneFixedOrder() {
        let line = TripRevealedLine.compose(
            .ru, km: "42 км", secrets: 1, riddles: 1, milestones: 1)
        XCTAssertEqual(line, "42 км нового пути\(sep)1 секрет\(sep)1 загадка\(sep)1 веха")
    }

    func testZeroPartsAreOmittedEntirely() {
        let line = TripRevealedLine.compose(
            .ru, km: "42 км", secrets: 0, riddles: 0, milestones: 2)
        XCTAssertEqual(line, "42 км нового пути\(sep)2 вехи")
        XCTAssertFalse(line.contains("0"), "нулевая часть просочилась: \(line)")
    }

    /// Километров нет — строка начинается с находок, а не с пустого места и
    /// не с разделителя.
    func testNoKilometresLeavesTheCountsAlone() {
        let line = TripRevealedLine.compose(
            .ru, km: nil, secrets: 1, riddles: 0, milestones: 0)
        XCTAssertEqual(line, "1 секрет")
    }

    func testEmptyKilometreStringCountsAsNoKilometres() {
        XCTAssertEqual(
            TripRevealedLine.compose(.ru, km: "", secrets: 0, riddles: 1, milestones: 0),
            "1 загадка")
    }

    /// Нечего показывать — пустая строка, а не «0 км нового пути». Блок с
    /// такой сводкой не рисуется вовсе (`TripDiscoveries.isEmpty`), и это
    /// второй замок на том же правиле.
    func testNothingFoundGivesAnEmptyLine() {
        XCTAssertEqual(
            TripRevealedLine.compose(.ru, km: nil, secrets: 0, riddles: 0, milestones: 0),
            "")
    }

    /// Порядок — километры, секрет, загадка, веха: от общего к личному, как
    /// и печати в `TripDiscoveries.all`.
    func testOrderIsKilometresThenSecretsThenRiddlesThenMilestones() {
        let line = TripRevealedLine.compose(
            .en, km: "26 mi", secrets: 2, riddles: 3, milestones: 4)
        let parts = line.components(separatedBy: sep)
        XCTAssertEqual(parts.count, 4)
        XCTAssertTrue(parts[0].contains("26 mi"), parts[0])
        XCTAssertTrue(parts[1].contains("secret"), parts[1])
        XCTAssertTrue(parts[2].contains("riddle"), parts[2])
        XCTAssertTrue(parts[3].contains("milestone"), parts[3])
    }

    // MARK: Склонения

    func testRussianCountedNounsTakeAllThreeForms() {
        XCTAssertEqual(AppStrings.nounSecrets(.ru, 1), "секрет")
        XCTAssertEqual(AppStrings.nounSecrets(.ru, 2), "секрета")
        XCTAssertEqual(AppStrings.nounSecrets(.ru, 5), "секретов")

        XCTAssertEqual(AppStrings.nounMilestones(.ru, 1), "веха")
        XCTAssertEqual(AppStrings.nounMilestones(.ru, 2), "вехи")
        XCTAssertEqual(AppStrings.nounMilestones(.ru, 5), "вех")
    }

    func testRussianLineDeclinesWithTheCount() {
        XCTAssertEqual(
            TripRevealedLine.compose(.ru, km: nil, secrets: 5, riddles: 0, milestones: 0),
            "5 секретов")
        XCTAssertEqual(
            TripRevealedLine.compose(.ru, km: nil, secrets: 0, riddles: 0, milestones: 11),
            "11 вех")
    }

    // MARK: Единица — чужая забота

    /// Строка не печатает расстояние сама: единица приезжает ГОТОВОЙ, вместе с
    /// числом, из `Measure`. Правило всей 0.6.7, и здесь оно держится тем, что
    /// подставленную строку композиция не трогает.
    func testKilometreTextIsPassedThroughUntouched() {
        let line = TripRevealedLine.compose(
            .en, km: "8.4 miles", secrets: 0, riddles: 0, milestones: 0)
        XCTAssertTrue(line.contains("8.4 miles"), line)
    }

    /// Подстановка доезжает на всех тринадцати языках: ряд, потерявший `{km}`,
    /// напечатал бы «нового пути» без числа.
    func testEveryLanguageKeepsThePlaceholder() {
        for lang in LanguageManager.Language.allCases {
            let text = AppStrings.revealedNewPath(lang, km: "42 km")
            XCTAssertTrue(text.contains("42 km"), "\(lang.rawValue): \(text)")
            XCTAssertFalse(text.contains("{km}"), "\(lang.rawValue): токен не подставлен — \(text)")
        }
    }

    func testTitleIsTranslatedEverywhere() {
        for lang in LanguageManager.Language.allCases {
            let title = AppStrings.revealedTitle(lang)
            XCTAssertFalse(title.isEmpty, lang.rawValue)
            XCTAssertNotEqual(title, "revealedTitle", lang.rawValue)
        }
    }
}
