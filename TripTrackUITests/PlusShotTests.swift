import XCTest

/// Кадры платной части: строка PRO в профиле, витрина, демонстрация, витрина
/// оформления, лист чаевых.
///
/// Картинки, а не утверждения: цена, длина триала, условия автопродления и
/// «Восстановить покупки» обязаны помещаться на экран ДО покупки, и проверить
/// это можно только глазами. Цены приезжают из `Config/TripTrack.storekit` —
/// та же конфигурация, что у схемы Run.
///
/// **Флаг — `-debug-pro-store`, а НЕ `-debug-plus`.** Второй делает
/// подписчика, а у подписчика продающих состояний не бывает вовсе: строка на
/// «Я» ведёт в управление подпиской App Store, замков нет, примерять нечего.
/// То есть состояния 1, 2, 12, 21, 23 — ровно те, на которые смотрит ревью
/// Apple, — с `-debug-plus` не снять ни одно; первая редакция этого тура
/// пыталась и падала на «пейвол не открылся».
///
/// Без флагов их не снять тоже: `PlusAvailability.isEnabled == false` (товаров
/// в App Store Connect ещё нет), и витрина считается спрятанной для всех.
/// Оба флага компилируются только в Debug.
final class PlusShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-debug-pro-store"]
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
        XCTAssertTrue(plusRow.waitForExistence(timeout: 6), "строки PRO нет в дереве")
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
        snap("w084_pro_row")

        plusRow.tap()
        let paywall = app.descendants(matching: .any)
            .matching(identifier: "plus_paywall").firstMatch
        XCTAssertTrue(paywall.waitForExistence(timeout: 6), "пейвол не открылся")
        // Цены приезжают из StoreKit асинхронно — кадр без них не тот кадр.
        usleep(2_500_000)

        // ЦЕНЫ В УТ-ПРОГОНЕ ЕСТЬ НЕ ВСЕГДА, и кадр обязан об этом СКАЗАТЬ.
        //
        // `storeKitConfiguration` из `project.yml` xcodegen 2.45 пишет только в
        // `LaunchAction`; у `TestAction` его в схеме НЕТ, хотя формат схемы это
        // поддерживает. Значит продукты в туре берутся из store симулятора,
        // засеянного прежним запуском ИЗ XCODE, — а на чистом симуляторе их
        // нет вовсе, и витрина честно показывает «цены не пришли».
        //
        // Молча снятый такой кадр — это скриншот для ревью Apple, на котором
        // вместо тарифов ошибка. Поэтому имя кадра говорит правду, и падением
        // это НЕ делается: на чистом симуляторе оно было бы шумом, а не
        // находкой.
        let plans = app.descendants(matching: .any)
            .matching(identifier: "pro_plans").firstMatch
        let pricesLoaded = plans.waitForExistence(timeout: 2)
        if !pricesLoaded {
            print("[shot] ЦЕНЫ НЕ ЗАГРУЗИЛИСЬ: в схеме у TestAction нет "
                  + "StoreKit-конфигурации. Кадр витрины НЕ годится для ревью — "
                  + "снимать его запуском из Xcode (Run), см. CLAUDE.md.")
        }
        snap(pricesLoaded ? "w084_paywall" : "w084_paywall_NO_PRICES")
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "plus_restore").firstMatch.exists,
            "«Восстановить покупки» обязана быть на экране — требование ревью")

        // Состояние 2: тап по строке набора открывает демонстрацию ЭТОЙ
        // функции — подвал с ценами при этом никуда не девается, и кадр это
        // показывает.
        let featureRow = app.buttons
            .matching(identifier: "pro_feature_photo.artframe").firstMatch
        if featureRow.waitForExistence(timeout: 4), featureRow.isHittable {
            featureRow.tap()
            let demo = app.descendants(matching: .any)
                .matching(identifier: "pro_demo").firstMatch
            XCTAssertTrue(demo.waitForExistence(timeout: 4), "демонстрация не открылась")
            usleep(1_200_000)
            snap("w084_demo")
            XCTAssertTrue(
                app.descendants(matching: .any)
                    .matching(identifier: "plus_restore").firstMatch.exists,
                "подвал с ценами обязан остаться и на демонстрации")
            app.buttons.matching(identifier: "pro_demo_back").firstMatch.tap()
            usleep(800_000)
        }

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
        // Подвал «Я» со строкой поддержки: её отсутствие в пустой ветке
        // профиля этот кадр и поймал.
        snap("w084_support_row")
        XCTAssertTrue(support.waitForExistence(timeout: 4), "строки «Поддержать» нет")
        support.tap()
        let jar = app.descendants(matching: .any).matching(identifier: "tip_jar").firstMatch
        XCTAssertTrue(jar.waitForExistence(timeout: 6), "лист чаевых не открылся")
        usleep(2_500_000)
        snap("w084_tipjar")
    }

    /// Витрина оформления (состояния 21…23): примерка платного НЕ уводит на
    /// пейвол — премиальная плитка выбирается, превью её показывает, и только
    /// кнопка внизу становится предложением.
    func test_showcase_tries_premium_on_without_a_paywall() {
        let recovery = app.buttons.matching(identifier: "recovery_continue").firstMatch
        if recovery.waitForExistence(timeout: 3), recovery.isHittable {
            recovery.tap(); sleep(2)
        }

        app.buttons.matching(identifier: "tab_profile").firstMatch.tap()
        usleep(1_500_000)

        // Хаб «Мой профиль» — через герой профиля.
        let hero = app.buttons.matching(identifier: "profile_avatar").firstMatch
        guard hero.waitForExistence(timeout: 6) else {
            XCTFail("героя профиля нет в дереве")
            return
        }
        hero.tap()
        usleep(1_500_000)

        let row = app.buttons.matching(identifier: "my_profile_row_background").firstMatch
        for _ in 0..<10 where !row.isHittable {
            app.swipeUp()
            usleep(300_000)
        }
        guard row.waitForExistence(timeout: 4), row.isHittable else {
            XCTFail("строки «Фон профиля» нет")
            return
        }
        row.tap()

        let showcase = app.descendants(matching: .any)
            .matching(identifier: "pro_showcase_photo.artframe").firstMatch
        XCTAssertTrue(showcase.waitForExistence(timeout: 6), "витрина не открылась")
        usleep(1_500_000)
        snap("w084_showcase")

        // Примерка: первая платная плитка.
        let premium = app.buttons.matching(identifier: "pro_tile_plus_nebula").firstMatch
        for _ in 0..<8 where !premium.isHittable {
            app.swipeUp()
            usleep(300_000)
        }
        if premium.isHittable {
            premium.tap()
            usleep(1_200_000)
            // Пейвол не открылся — витрина осталась на экране. Это и есть
            // принцип §1.4: витрины не выбрасывают на пейвол.
            XCTAssertTrue(showcase.exists, "примерка увела на пейвол — так нельзя")
            XCTAssertFalse(
                app.descendants(matching: .any)
                    .matching(identifier: "plus_paywall").firstMatch.exists,
                "пейвол открылся сам, без нажатия кнопки внизу")
            snap("w084_showcase_tryon")
        }
    }
}
