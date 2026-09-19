import XCTest

/// Кадры витрины «Плюса» (0.8.0): строка в профиле, пейвол, лист чаевых.
///
/// Всё три — картинки, а не утверждения: цена, длина триала, подвал
/// автопродления и «Восстановить покупки» обязаны помещаться на экран ДО
/// покупки, и проверить это можно только глазами. Цены приезжают из
/// `Config/TripTrack.storekit` — та же конфигурация, что у схемы Run.
final class PlusShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>"]
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test_plus_row_paywall_and_tip_jar() {
        // Восстановленная запись уводит с таб-бара — та же нормализация, что
        // у остальных туров.
        let recovery = app.buttons.matching(identifier: "recovery_continue").firstMatch
        if recovery.waitForExistence(timeout: 3), recovery.isHittable {
            recovery.tap(); sleep(2)
        }

        app.buttons.matching(identifier: "tab_profile").firstMatch.tap()
        usleep(1_500_000)

        let plusRow = app.buttons.matching(identifier: "profile_plus_row").firstMatch
        XCTAssertTrue(plusRow.waitForExistence(timeout: 6), "строки «Плюс» нет в дереве")
        // Содержимое профиля — обычный `VStack`, поэтому `.exists` истинно
        // задолго до того, как строка окажется НА экране. Крутим до
        // `isHittable`, как в остальных турах.
        for _ in 0..<10 where !plusRow.isHittable {
            app.swipeUp()
            usleep(300_000)
        }
        XCTAssertTrue(plusRow.isHittable, "строка «Плюс» не попала на экран")
        // Ещё два свайпа: «достижимо» наступает, когда строка только высунулась
        // из-под плавающего таб-бара, а на кадре она должна стоять целиком.
        app.swipeUp()
        usleep(400_000)
        app.swipeUp()
        usleep(600_000)
        snap("w080_plus_row")

        plusRow.tap()
        let paywall = app.descendants(matching: .any)
            .matching(identifier: "plus_paywall").firstMatch
        XCTAssertTrue(paywall.waitForExistence(timeout: 6), "пейвол не открылся")
        // Цены приезжают из StoreKit асинхронно — кадр без них не тот кадр.
        usleep(2_500_000)
        snap("w080_paywall")
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "plus_restore").firstMatch.exists,
            "«Восстановить покупки» обязана быть на экране — требование ревью")

        // Закрываем крестиком, а не свайпом: свайп по листу с прокручиваемым
        // содержимым уезжает в содержимое и лист не закрывает.
        app.descendants(matching: .any)
            .matching(identifier: "plus_close").firstMatch.tap()
        usleep(1_500_000)

        let support = app.buttons.matching(identifier: "profile_support_row").firstMatch
        for _ in 0..<10 where !support.isHittable {
            app.swipeUp()
            usleep(300_000)
        }
        XCTAssertTrue(support.waitForExistence(timeout: 4), "строки «Поддержать» нет")
        support.tap()
        let jar = app.descendants(matching: .any).matching(identifier: "tip_jar").firstMatch
        XCTAssertTrue(jar.waitForExistence(timeout: 6), "лист чаевых не открылся")
        usleep(2_500_000)
        snap("w080_tipjar")
    }
}
