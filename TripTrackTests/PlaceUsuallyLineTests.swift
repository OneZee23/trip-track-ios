import XCTest
@testable import TripTrack

/// Вторая строка карточки «Обычно занимает» (0.7.0, фикс-волна вёрстки).
///
/// Сторожит ровно то, на что пожаловался владелец: «1 ч 19 мин · 1 ч 19 мин ·
/// 1 проезд» — одно и то же число трижды. Разброс имеет право появиться только
/// когда он есть, и считается по НАПЕЧАТАННЫМ краям, а не по секундам.
final class PlaceUsuallyLineTests: XCTestCase {

    private let hour: TimeInterval = 3600

    // MARK: - Что показывается

    func testSinglePassShowsOnlyTheCount() {
        let line = PlaceUsuallyLine.compose(count: 1, best: hour, worst: hour, lang: .ru)
        XCTAssertEqual(line, "1 проезд")
    }

    func testTwoEqualPassesShowOnlyTheCount() {
        let line = PlaceUsuallyLine.compose(count: 2, best: hour, worst: hour, lang: .ru)
        XCTAssertEqual(line, "2 проезда")
    }

    func testTwoDifferentPassesShowTheRangeAndTheCount() {
        let line = PlaceUsuallyLine.compose(count: 2, best: hour, worst: hour + 1800, lang: .ru)
        XCTAssertEqual(line, "от 1 ч до 1 ч 30 мин · 2 проезда")
    }

    /// Округление до минут — то самое место, где «разброс» бывает мнимым:
    /// сорок секунд разницы печатаются одной и той же строкой.
    func testSecondsThatRoundToTheSameMinuteAreNotARange() {
        let line = PlaceUsuallyLine.compose(count: 3, best: hour, worst: hour + 40, lang: .ru)
        XCTAssertEqual(line, "3 проезда")
    }

    /// Перевёрнутая пара (лучшее больше худшего) не имеет права дать
    /// «от 1 ч 30 мин до 1 ч»: порядок нормализуется внутри.
    func testSwappedBoundsStillReadFromLowToHigh() {
        let line = PlaceUsuallyLine.compose(count: 2, best: hour + 1800, worst: hour, lang: .ru)
        XCTAssertEqual(line, "от 1 ч до 1 ч 30 мин · 2 проезда")
    }

    // MARK: - Числительные

    func testRussianPluralCountsOneTwoFive() {
        XCTAssertEqual(PlaceUsuallyLine.compose(count: 1, best: hour, worst: hour, lang: .ru), "1 проезд")
        XCTAssertEqual(PlaceUsuallyLine.compose(count: 2, best: hour, worst: hour, lang: .ru), "2 проезда")
        XCTAssertEqual(PlaceUsuallyLine.compose(count: 5, best: hour, worst: hour, lang: .ru), "5 проездов")
    }

    func testEnglishReadsAsASentence() {
        XCTAssertEqual(PlaceUsuallyLine.compose(count: 1, best: hour, worst: hour, lang: .en), "1 pass")
        XCTAssertEqual(
            PlaceUsuallyLine.compose(count: 3, best: hour, worst: hour + 1800, lang: .en),
            "from 1 h to 1 h 30 min · 3 passes")
    }

    // MARK: - Ключи направления

    /// Подстановка обязана быть заполнена на ВСЕХ тринадцати языках: `tr`
    /// отдаёт готовую строку из таблицы, и токен, потерянный в переводе,
    /// молча съел бы имя города.
    func testTowardsKeepsTheNameInEveryLanguage() {
        for lang in LanguageManager.Language.allCases {
            let text = AppStrings.placeTowards(lang, name: "Джубга")
            XCTAssertTrue(text.contains("Джубга"), "\(lang.rawValue): имя потерялось в «\(text)»")
            XCTAssertFalse(text.contains("{name}"), "\(lang.rawValue): токен остался в «\(text)»")
        }
    }

    func testRangeKeepsBothBoundsInEveryLanguage() {
        for lang in LanguageManager.Language.allCases {
            let text = AppStrings.placeUsuallyRange(lang, min: "АА", max: "ББ")
            XCTAssertTrue(text.contains("АА") && text.contains("ББ"),
                          "\(lang.rawValue): край потерялся в «\(text)»")
            XCTAssertFalse(text.contains("{min}") || text.contains("{max}"),
                           "\(lang.rawValue): токен остался в «\(text)»")
        }
    }

    /// «от старта» — хвост фразы, и своим ключом, а не `lowercased()`: у
    /// немецкого «Start» существительное, и строчная в нём — ошибка.
    func testInlineFromStartIsNotJustTheLowercasedHeader() {
        XCTAssertEqual(AppStrings.placeFromStartInline(.ru), "от старта")
        XCTAssertEqual(AppStrings.placeFromStartInline(.en), "from start")
        XCTAssertEqual(AppStrings.placeFromStartInline(.de), "ab Start")
    }
}
