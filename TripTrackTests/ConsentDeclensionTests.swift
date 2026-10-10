import XCTest
@testable import TripTrack

/// Согласие на первом экране онбординга склоняет названия документов.
/// Это уже чинилось (92fb6214) и тихо сломалось при переносе строк в таблицы:
/// ссылки стали брать именительные заголовки, и человек читал «соглашаетесь с
/// Условия использования и Политика конфиденциальности».
final class ConsentDeclensionTests: XCTestCase {
    private func text(_ lang: LanguageManager.Language) -> String {
        AppStrings.onboardingConsentMarkdown(lang, termsURL: "t", privacyURL: "p")
    }

    func testRussianUsesInstrumental() {
        XCTAssertTrue(text(.ru).contains("[Условиями использования](t)"))
        XCTAssertTrue(text(.ru).contains("[Политикой конфиденциальности](p)"))
    }

    func testUkrainianUsesInstrumental() {
        XCTAssertTrue(text(.uk).contains("[Умовами використання](t)"))
        XCTAssertTrue(text(.uk).contains("[Політикою конфіденційності](p)"))
    }

    func testPolishAndKazakhUseAccusative() {
        XCTAssertTrue(text(.pl).contains("[Politykę prywatności](p)"))
        XCTAssertTrue(text(.kk).contains("[Пайдалану шарттарын](t)"))
        XCTAssertTrue(text(.kk).contains("[Құпиялық саясатын](p)"))
    }

    /// Заголовки сами по себе остаются в именительном — их читают кнопки.
    func testStandaloneTitlesStayNominative() {
        XCTAssertEqual(AppStrings.termsOfService(.ru), "Условия использования")
        XCTAssertEqual(AppStrings.privacyPolicy(.ru), "Политика конфиденциальности")
    }

    func testEveryLanguageLinksBothDocuments() {
        for lang in LanguageManager.Language.allCases {
            XCTAssertTrue(text(lang).contains("](t)"), "\(lang)")
            XCTAssertTrue(text(lang).contains("](p)"), "\(lang)")
        }
    }
}
