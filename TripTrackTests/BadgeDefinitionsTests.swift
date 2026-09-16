import XCTest
@testable import TripTrack

/// Именной значок авторского секрета.
///
/// Его открывает не статистика поездок, а разбор трека: `DiscoveryProcessor`
/// зовёт `unlock("secret_" + ключ находки)`. Значит `id` значка, `id` записи
/// в `Secrets.json` и `id` строки в серверной таблице `secret` — три
/// написания ОДНОГО ключа, и разойтись им нельзя: значок просто никогда не
/// откроется, без единой ошибки.
final class BadgeDefinitionsTests: XCTestCase {

    private func komsomolsky() throws -> Badge {
        try XCTUnwrap(Badge.all.first { $0.id == "secret_komsomolsky" })
    }

    func testKomsomolskyBadgeExistsHiddenAndEpic() throws {
        let badge = try komsomolsky()
        XCTAssertTrue(badge.isHidden)
        XCTAssertEqual(badge.category, .exploration)
        XCTAssertEqual(badge.rarity, .epic)
        XCTAssertEqual(badge.titleRu, "Знак Комсомольского")
        XCTAssertEqual(badge.titleEn, "The Komsomolsky Mark")
        XCTAssertEqual(badge.descriptionRu, "Проехать через Комсомольский в Краснодаре")
        XCTAssertEqual(badge.descriptionEn, "Drive through Komsomolsky in Krasnodar")
    }

    /// Не выводится из статистики — иначе пересчёт открывал бы его тому, кто
    /// в Краснодаре не был.
    func testKomsomolskyBadgeIsNeverInferredFromStats() throws {
        let badge = try komsomolsky()
        XCTAssertFalse(badge.checkUnlocked(BadgeManager.computeStats(from: [])))
        XCTAssertTrue(Badge.externallyUnlockedIds.contains("secret_komsomolsky"),
                      "без этого пересчёт статистики стирал бы значок с полки")
    }

    /// `secret_` + id секрета из бандла. Ключ собирается СТРОКОЙ в
    /// `DiscoveryProcessor.unlockBadges`, и компилятор здесь не помогает.
    func testBadgeIdMatchesTheBundledSecretId() throws {
        let ids = BundleSecretCatalog().all().map(\.id)
        XCTAssertTrue(ids.contains("komsomolsky"))
        XCTAssertEqual("secret_" + "komsomolsky", try komsomolsky().id)
    }

    /// Значки не повторяются по id: дубль тихо победил бы по порядку в
    /// массиве, а какой именно — зависит от места вставки.
    func testBadgeIdsAreUnique() {
        let ids = Badge.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }
}
