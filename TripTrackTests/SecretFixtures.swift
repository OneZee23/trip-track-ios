import XCTest
@testable import TripTrack

/// Настоящие хеши Комсомольского — для ТЕСТОВ, а не для бандла приложения.
///
/// В 0.7.0 `TripTrack/Resources/Secrets.json` уезжает ПУСТЫМ: авторский
/// секрет приходит каталогом с сервера после активации строки, и до неё
/// проезд через район не даёт ничего (иначе человек получил бы безымянную
/// печать и именной эпический значок раньше, чем у секрета появилась
/// история). Но арифметику — 139 ячеек, усечение SHA-256, площадной матчинг —
/// проверять надо на НАСТОЯЩЕЙ записи, а не на выдуманной: разойдясь на байт,
/// телефон и сервер дали бы секрет, который находится, но не подтверждается.
///
/// Поэтому запись живёт фикстурой `Fixtures/Secrets-komsomolsky.json` (та же,
/// что печатает `Tools/build_secrets.py --authored`), а тесты читают её через
/// `BundleSecretCatalog(url:)` — тот же разбор, тот же формат, просто другой
/// файл.
enum SecretFixtures {

    /// Каталог из фикстуры. `nil` невозможен: файл лежит в ресурсах тестового
    /// бандла, и его отсутствие — сломанная сборка, о которой тест обязан
    /// сказать словами.
    static func komsomolskyCatalog(file: StaticString = #filePath,
                                   line: UInt = #line) throws -> BundleSecretCatalog {
        let url = try XCTUnwrap(
            Bundle(for: SecretFixtureToken.self)
                .url(forResource: "Secrets-komsomolsky", withExtension: "json"),
            "фикстура Secrets-komsomolsky.json не попала в ресурсы тестового бандла",
            file: file, line: line)
        return BundleSecretCatalog(url: url)
    }

    /// Запись секрета и соль каталога — то, что нужно матчеру.
    static func komsomolsky(file: StaticString = #filePath,
                            line: UInt = #line) throws -> (record: SecretRecord, salt: String) {
        let catalog = try komsomolskyCatalog(file: file, line: line)
        let record = try XCTUnwrap(catalog.all().first { $0.id == "komsomolsky" },
                                   "в фикстуре нет записи komsomolsky", file: file, line: line)
        return (record, catalog.salt)
    }
}

/// Якорь для `Bundle(for:)`: фикстуры лежат в тестовом бандле, а он ищется по
/// классу.
private final class SecretFixtureToken {}
