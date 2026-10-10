import XCTest

/// Кадры текстов, исправленных в 0.8.9 (docs/releases/0.8.9/honest-copy.md):
/// карточка-пример онбординга и экран геолокации. Ничего не утверждает про
/// разрешения — только снимает, что видит человек. Кадры уходят в результат
/// прогона как вложения.
@MainActor
final class HonestCopyShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func launch(page: Int, lang: String) {
        app.launchArguments = [
            "-ui-test-onboarding", "-onboardingStartPage", "\(page)",
            "-appLanguage", lang, "-AppleLanguages", "(\(lang))",
        ]
        app.launch()
    }

    func testSampleTripCardRu() {
        launch(page: 1, lang: "ru")
        XCTAssertTrue(app.staticTexts["Пример"].waitForExistence(timeout: 5),
                      "a mock trip must be labelled as an example, not as recorded")
        capture("onboarding-sample-ru")
    }

    func testSampleTripCardEn() {
        launch(page: 1, lang: "en")
        XCTAssertTrue(app.staticTexts["Example"].waitForExistence(timeout: 5))
        capture("onboarding-sample-en")
    }

    func testLocationExplanationRu() {
        launch(page: 2, lang: "ru")
        XCTAssertTrue(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS 'покидают телефон'")).firstMatch.waitForExistence(timeout: 5))
        capture("onboarding-location-ru")
    }
}
