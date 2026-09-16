import XCTest

/// Кадр секции «Находки» на публичном профиле (0.7.0, wave 4 task 4).
///
/// Секцию своим ходом не увидеть: печати верифицируются на сервере, а его на
/// симуляторе нет. `-debug-profile-finds` подменяет `loadProfile()` готовым
/// DTO (`SocialProfile.debugFindsSample`, `PublicProfileView.swift`, под
/// `#if DEBUG`) — тот же приём, что `-debug-admin` у карточки «Админ»
/// (`AdminCardShotTests`).
///
/// Вход в чужой профиль — `app.open(...)` на `triptrack://profile/<uuid>`,
/// тот же диплинк, что шлёт сайт (`TripTrackApp.handleDeepLink`, кейс
/// `"profile"`/`"u"`). Он не спрашивает вход в аккаунт — в отличие от «Как
/// видят другие» в настройках приватности, которой нужен
/// `TokenStore.shared.accountId`, и которая поэтому не годится для
/// самостоятельного UI-теста на чистом симуляторе.
final class PublicProfileFindsShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-debug-profile-finds"]
        app.launch()
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test_profile_finds_section() {
        // Восстановленная запись уводит с таб-бара — та же нормализация, что
        // у остальных туров (см. `AdminCardShotTests`).
        let recovery = app.buttons.matching(identifier: "recovery_continue").firstMatch
        if recovery.waitForExistence(timeout: 3), recovery.isHittable {
            recovery.tap(); sleep(2)
        }

        app.open(URL(string: "triptrack://profile/11111111-1111-4111-8111-111111111111")!)

        let finds = app.descendants(matching: .any)
            .matching(identifier: "profile_finds").firstMatch
        XCTAssertTrue(finds.waitForExistence(timeout: 6), "секции «Находки» нет в дереве")

        // `ScrollView`'s content is a plain `VStack`, not `LazyVStack` — every
        // card exists in the accessibility tree from the first frame, so
        // `.exists` is true well before the card is ON screen. Swipe by a
        // fixed count instead, until the card is actually hittable.
        for _ in 0..<10 where !finds.isHittable {
            app.swipeUp()
            usleep(300_000)
        }
        XCTAssertTrue(finds.isHittable, "секция «Находки» не попала на экран после прокрутки")
        snap("w070_w4_profile_finds")
    }
}
