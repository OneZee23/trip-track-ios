import XCTest

/// The second onboarding page fits its phone (0.8.9).
///
/// Until 0.8.9 «Вот как выглядит ваша поездка» was one scrolling column 143 pt
/// taller than an iPhone 16: «Дальше» started below the edge and the page
/// dots — an overlay — sat on the caption. Every new user saw it, not only
/// people with trips: the sample card is as tall as a real one.
///
/// Checked in all thirteen languages, because the page fits an iPhone 16 with
/// a couple of points to spare and a title that wraps to a third line would
/// spend them: «Дальше» is on screen without a swipe and ends above the dots,
/// nothing readable sits under the dots, and on an iPhone 15/16-class screen
/// nothing scrolls at all.
@MainActor
final class OnboardingValuePageTests: XCTestCase {
    private let languages = ["ru", "en", "de", "es", "fr", "it", "pl", "id", "tr", "fil", "uk", "kk", "pt"]

    func testContinueIsOnScreenAndNothingSitsUnderThePageDots() {
        continueAfterFailure = false
        for code in languages {
            let app = XCUIApplication()
            app.launchArguments = [
                "-ui-test-onboarding", "-onboardingStartPage", "1", "-seed-map-demo",
                "-appLanguage", code, "-AppleLanguages", "(\(code))", "-appThemeMode", "light",
            ]
            app.launch()
            let next = app.buttons["onboarding_continue_value"].firstMatch
            XCTAssertTrue(next.waitForExistence(timeout: 30), code)
            sleep(1)
            let window = app.windows.firstMatch.frame
            if code == "ru" {
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "onboarding_value_ru_\(Int(window.height))"
                shot.lifetime = .keepAlways
                add(shot)
            }

            // The dots: 7 pt tall, 12 pt above the bottom of the safe area —
            // 34 pt on a phone with a home indicator, none on an iPhone SE.
            let bottomInset: CGFloat = window.height > 700 ? 34 : 0
            let dotsTop = window.maxY - bottomInset - 12 - 7
            let dotsBottom = dotsTop + 7

            XCTAssertTrue(next.isHittable, "\(code): «Дальше» must be on screen without a swipe")
            XCTAssertLessThanOrEqual(next.frame.maxY, dotsTop + 0.5,
                                     "\(code): «Дальше» must end above the dots (\(next.frame))")

            // Text a person can see — hittable, not clipped by a scroll view —
            // must not cross the dots strip.
            for text in app.staticTexts.allElementsBoundByIndex
            where text.frame.minY < dotsBottom && text.frame.maxY > dotsTop && text.isHittable {
                XCTFail("\(code): «\(text.label)» sits under the page dots (\(text.frame))")
            }

            if window.height >= 844 {
                XCTAssertEqual(app.scrollViews.count, 0,
                               "\(code): on an iPhone 15/16 the page must fit without scrolling")
            }
            app.terminate()
        }
    }
}
