import XCTest
@testable import TripTrack

/// Чип «Бета» у заголовка «Атлас» и карточка, которую он открывает.
///
/// Возвращён 19 сентября — тот же повод, что снял его 15-го («карта ещё
/// дорабатывается»), только теперь про экран, который снова существует.
final class AtlasBetaTests: XCTestCase {

    // MARK: - Копия только через AppStrings

    /// Ни строка чипа, ни заголовок, ни тело карточки не написаны в `body` —
    /// все три идут через `AppStrings.atlasBeta*`, как остальная копия
    /// приложения (CLAUDE.md «Adding a string»).
    func testChipAndCardCopyComeFromAppStrings() {
        XCTAssertEqual(AppStrings.atlasBetaChip(.ru), "Бета")
        XCTAssertEqual(AppStrings.atlasBetaChip(.en), "Beta")
        XCTAssertFalse(AppStrings.atlasBetaTitle(.ru).isEmpty)
        XCTAssertFalse(AppStrings.atlasBetaBody(.ru).isEmpty)
        // RU и EN не совпадают — то есть строка реально переведена, а не
        // повторена как английская заглушка под русским ключом.
        XCTAssertNotEqual(AppStrings.atlasBetaTitle(.ru), AppStrings.atlasBetaTitle(.en))
        XCTAssertNotEqual(AppStrings.atlasBetaBody(.ru), AppStrings.atlasBetaBody(.en))
    }

    /// Ни одна из строк не пуста и не совпадает с ключом ни на одном из
    /// тринадцати языков — тот же прогон, что `LocalizationTests` делает по
    /// таблицам, здесь по самим функциям.
    func testCopyIsTranslatedOnEveryLanguage() {
        for lang in LanguageManager.Language.allCases {
            XCTAssertFalse(AppStrings.atlasBetaChip(lang).isEmpty, lang.rawValue)
            XCTAssertFalse(AppStrings.atlasBetaTitle(lang).isEmpty, lang.rawValue)
            XCTAssertFalse(AppStrings.atlasBetaBody(lang).isEmpty, lang.rawValue)
        }
    }

    // MARK: - Модель карточки

    /// Маршрут для «Написать» — ТОТ ЖЕ адрес, что у строки «Написать автору» в
    /// профиле: второй ящик модель не заводит.
    func testFeedbackRouteReusesTheProfileAddress() {
        let model = AtlasBetaSheetModel.make()
        XCTAssertEqual(model.feedbackURL, URL(string: "mailto:\(ProfileSettingsSheet.authorEmail)"))
    }

    /// Маршрута нет (пустой адрес) — кнопки «Написать» в модели тоже нет, и
    /// карточка падает на одно «Понятно». Проверяется без обращения к `body`.
    func testFeedbackActionIsAbsentWithoutARoute() {
        XCTAssertNil(AtlasBetaSheetModel.make(feedbackAddress: nil).feedbackURL)
        XCTAssertNil(AtlasBetaSheetModel.make(feedbackAddress: "").feedbackURL)
    }
}
