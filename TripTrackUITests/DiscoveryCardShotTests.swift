import XCTest

/// Кадры карточки находки (0.7.0, волна 4): загадка и веха.
///
/// Модель карточки держат числами `DiscoveryCardModelTests`, но они не
/// отвечают на вопрос «влезло ли и видно ли»: у загадки под текстом стоит
/// мини-карта со снимком MapKit и кругом поверх него, и нарисован ли круг там,
/// где думает вью, проверяется только снимком.
///
/// Секрет добавлен в волне 5: сид кладёт «Знак Комсомольского» со всеми полями,
/// какие бывают у находки (имя, счётчик нашедших, первооткрыватель), кроме
/// истории — её на месте держит Debug-заглушка, ровно как до ответа
/// `/secrets/reveal`. До волны 5 секрета в этих кадрах не было и быть не могло:
/// каталог хранит одни хеши, а имя и счётчик приходят с сервера.
final class DiscoveryCardShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo", "-seed-discoveries",
        ]
        app.launch()
    }

    /// Перезапуск с включённым Cloud Sync.
    ///
    /// Своего Debug-аргумента у облака нет, и выдумывать его для одного кадра
    /// не нужно: `cloudSyncEnabled` читается из `UserDefaults`, а домен
    /// аргументов запуска перекрывает прикладной — тем же способом, которым
    /// весь набор передаёт `-hasCompletedOnboarding`. Вторым ключом гасится
    /// разовая миграция «синк строго по согласию»: она на первом запуске
    /// возвращает флаг в `false`, и без неё кадр показал бы выключённое облако.
    private func relaunchWithCloudSync() {
        app.terminate()
        app.launchArguments += [
            "-com.triptrack.settings.cloudSyncOptInMigrationV1", "<true/>",
            "-com.triptrack.settings.cloudSyncEnabled", "<true/>",
        ]
        app.launch()
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Журнал открыт, сетка печатей на экране.
    private func openJournal() {
        let tab = app.buttons.matching(identifier: "tab_maps").firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 12), "вкладка «Атлас» на месте")
        tab.tap()
        // Туман выгорает 0.7 с, карта успевает встать за пару секунд.
        usleep(3_500_000)

        let summary = app.otherElements["mymap_summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "свёрнутый лист поднят")
        summary.tap()
        usleep(2_000_000)
        XCTAssertTrue(app.otherElements["mymap_region_list"].waitForExistence(timeout: 8),
                      "журнал открылся")
    }

    /// Печать ищется ПО ПОДПИСИ вида ВНУТРИ ЖУРНАЛА.
    ///
    /// По подписи, а не по месту в сетке: у обеих находок сида одна дата, и
    /// порядок между ними ничем не закреплён. Внутри журнала, а не по всему
    /// экрану: те же печати стоят и на карте под панелью, и первым совпадением
    /// приходила именно карта — тап по ней уходил в «hit point {-1, -1}».
    private func tapSeal(kind: String, or alternative: String? = nil) {
        let predicate = alternative.map {
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", kind, $0)
        } ?? NSPredicate(format: "label CONTAINS[c] %@", kind)
        let seal = app.otherElements["mymap_region_list"].buttons.matching(predicate).firstMatch
        XCTAssertTrue(seal.waitForExistence(timeout: 8), "печать «\(kind)» в сетке журнала")
        seal.tap()
        XCTAssertTrue(app.otherElements["mymap_discovery_card"].waitForExistence(timeout: 8),
                      "карточка находки открылась")
    }

    func test_card_riddle() {
        openJournal()
        tapSeal(kind: "riddle")
        // Мини-карта тянет тайлы сетью — без паузы в кадр попадает пустой
        // прямоугольник с одним кругом.
        usleep(9_000_000)
        snap("w070_w4_card_riddle")
    }

    func test_card_milestone() {
        openJournal()
        tapSeal(kind: "milestone")
        usleep(1_500_000)
        snap("w070_w4_card_milestone")
    }

    /// Карточка секрета: печать крупно, имя, история-заглушка — и НИ СЛОВА про
    /// нашедших, пока Cloud Sync выключен.
    ///
    /// Счётчик в базе лежит (сид кладёт `finders: 7` и имя первого), и это
    /// главное в кадре: строка молчит не потому, что нечего показать, а потому,
    /// что без облака мы сервер не спрашивали. Ноль на её месте был бы враньём,
    /// а не осторожностью.
    func test_secret_card() {
        openJournal()
        tapSeal(kind: "secret", or: "секрет")
        usleep(1_500_000)
        snap("w070_w5_card_secret")

        let card = app.otherElements["mymap_discovery_card"]
        XCTAssertFalse(
            card.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'OneZee'")).firstMatch.exists,
            "без Cloud Sync строки «нашли N · первым — имя» на карточке нет")
    }

    /// Тот же секрет с включённым облаком: строка нашедших на месте.
    func test_secret_card_with_cloud_sync() {
        relaunchWithCloudSync()
        openJournal()
        tapSeal(kind: "secret", or: "секрет")
        usleep(1_500_000)
        snap("w070_w5_card_secret_cloud")

        let card = app.otherElements["mymap_discovery_card"]
        XCTAssertTrue(
            card.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'OneZee'")).firstMatch
                .waitForExistence(timeout: 4),
            "с Cloud Sync карточка называет первооткрывателя")
    }
}
