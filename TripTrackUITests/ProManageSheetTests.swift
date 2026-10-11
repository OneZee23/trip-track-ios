import StoreKitTest
import XCTest

/// «Ваш PRO» — экран подписчика перед листом Apple (0.8.9).
///
/// Три обещания, и каждое проверяется настоящей покупкой из конфигурации
/// StoreKit, а не флагом: у `-debug-plus` нет ни даты, ни тарифа, ни признака
/// продления, то есть строку о подписке на нём не задать вовсе.
///
/// 1. Строка PRO на «Я» ведёт подписчика сюда, а не сразу в лист Apple.
/// 2. Строка о подписке называет дату и цену, а после отключения продления —
///    «работает до» БЕЗ цены: экран не обещает списания, которого не будет.
/// 3. «Управлять подпиской в App Store» видна БЕЗ ПРОКРУТКИ — и при самом
///    крупном тексте. Отмена остаётся в двух касаниях (правило ревью 3.1.2 и
///    законы о простом отказе от подписки); прятать её глубже нельзя.
///
/// Изолированный симулятор, `API_BASE_URL=http://127.0.0.1:1` — ни аккаунта
/// Apple, ни входа на сервер этому тесту не нужно.
@MainActor
final class ProManageSheetTests: XCTestCase {
    private var app: XCUIApplication!
    private var store: SKTestSession!
    private let yearlyID = "com.onezee.TripTrack.pro.yearly"

    override func setUpWithError() throws {
        continueAfterFailure = false
        let configuration = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "TripTrack", withExtension: "storekit"))
        store = try SKTestSession(contentsOf: configuration)
        store.resetToDefaultState()
        store.clearTransactions()
        store.disableDialogs = true
        store.timeRate = .realTime
        store.storefront = "DEU"
    }

    override func tearDownWithError() throws {
        app?.terminate()
        store?.clearTransactions()
        store?.resetToDefaultState()
        app = nil
        store = nil
    }

    private func launch(largeText: Bool = false) {
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-debug-pro-store",
            "-appLanguage", "ru", "-AppleLanguages", "(ru)", "-AppleLocale", "de_DE",
            "-UIPreferredContentSizeCategoryName",
            largeText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL",
        ]
        app.launch()
    }

    func testSubscriberSeesTheirProBeforeAppleAndCanStillReachIt() throws {
        launch()
        buyYearly()
        openManage()

        let line = element("pro_manage_line")
        waitFor(line, timeout: 20)
        XCTAssertTrue(line.label.hasPrefix("Пробный период до"), line.label)
        XCTAssertTrue(line.label.contains("€") && line.label.hasSuffix("в год"),
                      "Пробный период называет цену после него: «\(line.label)»")
        assertAppStoreRowVisible()
        snap("pro_manage_trial")

        // Отменил продление в App Store — экран больше не обещает списание.
        let purchase = try XCTUnwrap(store.allTransactions().first { $0.productIdentifier == yearlyID })
        try store.disableAutoRenewForTransaction(identifier: purchase.identifier)
        tap("pro_manage_close")
        XCUIDevice.shared.press(.home)
        app.activate()
        // Права перечитываются через две секунды после возвращения.
        sleep(4)
        openManage()
        let ended = element("pro_manage_line")
        let off = NSPredicate(format: "label BEGINSWITH 'Продление отключено'")
        expectation(for: off, evaluatedWith: ended)
        waitForExpectations(timeout: 20)
        XCTAssertFalse(ended.label.contains("€"),
                       "Отменившему продление цена не печатается: «\(ended.label)»")
        assertAppStoreRowVisible()
        snap("pro_manage_renewal_off")
    }

    /// При самом крупном тексте пять строк функций выше экрана — а строка App
    /// Store всё равно на нём: она приколочена под списком, а не в его конце.
    func testAppStoreRowIsVisibleWithoutScrollingAtTheLargestText() {
        launch(largeText: true)
        buyYearly()
        openManage()
        waitFor(element("pro_manage_line"), timeout: 20)
        assertAppStoreRowVisible()
        snap("pro_manage_large_text")
    }

    /// Функция открывает СВОЮ витрину — после закрытия листа, а не поверх него.
    func testFeatureRowOpensItsShowcase() {
        launch()
        buyYearly()
        openManage()
        tap("pro_manage_photo.artframe")
        waitFor(element("pro_showcase_photo.artframe"), timeout: 10)
        assertAbsent(element("pro_manage"))
    }

    // MARK: - Шаги

    private func buyYearly() {
        openProfileRow()
        tap("profile_plus_row")
        waitFor(element("pro_plans"), timeout: 20)
        tap("pro_plan_\(yearlyID)")
        tap("plus_buy")
        waitFor(button("pro_bought_later"), timeout: 20)
        tap("pro_bought_later")
        assertAbsent(element("plus_paywall"))
    }

    private func openManage() {
        openProfileRow()
        tap("profile_plus_row")
        waitFor(element("pro_manage"), timeout: 10)
        // Строка PRO ведёт подписчика на свой экран, а не в лист Apple.
        assertAbsent(element("plus_paywall"))
    }

    private func openProfileRow() {
        let tab = button("tab_profile")
        waitFor(tab, timeout: 40)
        tab.tap()
        let sections = button("profile_sections_toggle")
        if sections.waitForExistence(timeout: 3), !button("profile_plus_row").isHittable {
            reveal(sections)
            sections.tap()
        }
        reveal(button("profile_plus_row"))
    }

    private func assertAppStoreRowVisible() {
        let row = button("pro_manage_app_store")
        waitFor(row)
        XCTAssertTrue(row.isHittable, "Строка App Store обязана нажиматься без прокрутки")
        XCTAssertLessThanOrEqual(row.frame.maxY, app.windows.firstMatch.frame.maxY,
                                 "Строка App Store обязана стоять на экране целиком")
        XCTAssertGreaterThanOrEqual(row.frame.height, 44, "Строка App Store — 44 pt и выше")
    }

    // MARK: - Помощники

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func button(_ id: String) -> XCUIElement {
        app.buttons.matching(identifier: id).firstMatch
    }

    private func tap(_ id: String) {
        let target = button(id)
        waitFor(target)
        target.tap()
    }

    private func waitFor(_ target: XCUIElement, timeout: TimeInterval = 15) {
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "\(target) did not appear")
    }

    private func assertAbsent(_ target: XCUIElement) {
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: target)
        waitForExpectations(timeout: 10)
    }

    private func reveal(_ target: XCUIElement) {
        let window = app.windows.firstMatch
        for _ in 0..<10 where !(target.exists && target.isHittable)
            || target.frame.maxY > window.frame.height - 130 {
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -220)),
                       withVelocity: .slow, thenHoldForDuration: 0.2)
        }
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
