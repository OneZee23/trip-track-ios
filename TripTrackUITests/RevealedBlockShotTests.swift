import XCTest

/// Кадр блока «Открыто» на экране итогов (0.7.0).
///
/// Юнит-тесты держат строку и выгорание, но не отвечают на вопрос «видно ли
/// его вообще»: блок стоит между плитками и значками, а мини-карта под ним —
/// настоящий `MKMapView` с туманом, который на снимке может оказаться ровным
/// чёрным прямоугольником.
///
/// Экран открывается отладочным входом «Экран финиша (отладка)» — как в
/// `FinishScreenTests`; `-seed-discoveries` кладёт на демо-поездку две
/// находки, а отладочный вход перештамповывает их на показанную поездку.
final class RevealedBlockShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo", "-seed-discoveries",
        ]
        app.launch()
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test_revealed_block_on_the_finish_screen() {
        app.buttons.matching(identifier: "tab_profile").firstMatch.tap()
        usleep(1_500_000)

        let gear = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'gearshape'")).firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 8), "у профиля есть шестерёнка")
        gear.tap()
        usleep(1_500_000)

        let debugRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'финиша' OR label CONTAINS 'Finish screen'")).firstMatch
        for _ in 0..<6 where !debugRow.exists {
            app.swipeUp()
            usleep(500_000)
        }
        XCTAssertTrue(debugRow.waitForExistence(timeout: 4), "отладочный вход на месте")
        debugRow.tap()
        usleep(3_500_000)

        XCTAssertTrue(app.buttons.matching(identifier: "summary_done").firstMatch.exists,
                      "экран итогов открылся")

        // Блок стоит ниже плиток — до него надо доскроллить; сводка находок
        // приезжает позже остальных чисел, поэтому ждём её появления.
        let block = app.descendants(matching: .any)
            .matching(identifier: "summary_revealed").firstMatch
        for _ in 0..<4 where !block.exists {
            app.swipeUp()
            usleep(700_000)
        }
        XCTAssertTrue(block.waitForExistence(timeout: 8), "блок «Открыто» на экране итогов")
        // Выгорание тумана — 0.7 с; снимок после него.
        usleep(1_500_000)
        snap("w070_w2_summary")
    }
}
