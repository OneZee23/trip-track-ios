import XCTest
@testable import TripTrack

/// Sentry молчал ДЕСЯТЬ релизов, и причина была не та, что записана.
///
/// Записано было «`SENTRY_DSN` живёт в `Local.xcconfig`, подставляется в
/// `Info.plist` и читается `AppConfig.sentryDSN`; пусто — `SentryService`
/// выходит на первом `guard`». Всё верно, кроме середины: строки
/// `<key>SENTRY_DSN</key><string>$(SENTRY_DSN)</string>` в шаблоне
/// `TripTrack/Info.plist` не существовало НИ РАЗУ за всю историю файла
/// (`git log -S'SENTRY_DSN' -- TripTrack/Info.plist` — пусто). Переменную
/// xcconfig подставляет в plist только сам plist; `project.yml` про неё не
/// знает и знать не обязан, а `AppConfig` получал `nil` и молчал ровно так
/// же, как молчал бы на пустом ключе.
///
/// **Проверяется СОБРАННЫЙ продукт, а не исходник.** Вопрос здесь ровно один
/// — доехало ли значение до артефакта, — и ответить на него может только
/// артефакт: исходник «выглядит рабочим» и в той версии, где ничего не
/// работало. Тестовый бандл лежит в той же папке Products, что и
/// `TripTrack.app`, поэтому искать его не нужно.
///
/// Тест НЕ требует непустого DSN: `Local.xcconfig` задаёт его только для
/// Release, а Debug там пуст сознательно (символы сборки без ключа в
/// кабинете не нужны). Требуется другое — чтобы ключ СУЩЕСТВОВАЛ и чтобы в
/// нём лежало то, что сказал xcconfig, а не нераскрытая подстановка.
final class SentryDSNWiringTests: XCTestCase {

    /// Собранный `TripTrack.app`. Ищется ДВУМЯ способами, потому что размещение
    /// тестового бандла зависит от того, есть ли у цели хост: с хостом он лежит
    /// внутри `TripTrack.app/PlugIns`, без хоста — рядом с ним в Products.
    /// Пропустить тест, не найдя приложения, было бы худшим видом зелёного,
    /// поэтому здесь падение с объяснением, а не `XCTSkip`.
    private func builtAppInfoPlist() throws -> [String: Any] {
        var url = Bundle(for: Self.self).bundleURL
        var app: URL?
        while url.pathComponents.count > 1 {
            if url.pathExtension == "app" { app = url; break }
            url = url.deletingLastPathComponent()
        }
        if app == nil {
            let sibling = Bundle(for: Self.self).bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("TripTrack.app")
            if FileManager.default.fileExists(atPath: sibling.path) { app = sibling }
        }
        let bundle = try XCTUnwrap(app, "собранный TripTrack.app не найден ни внутри, ни рядом")
        let data = try Data(contentsOf: bundle.appendingPathComponent("Info.plist"))
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any],
            "Info.plist собранного продукта не разобрался")
    }

    /// Ключ есть в артефакте, и в нём не осталось `$(…)`.
    func testTheBuiltAppCarriesTheSentryKey() throws {
        let info = try builtAppInfoPlist()
        let value = info["SENTRY_DSN"] as? String
        XCTAssertNotNil(
            value,
            """
            в собранном TripTrack.app нет ключа SENTRY_DSN — значит Sentry \
            не запустится ни в одной сборке, как не запускался с 0.5.x. \
            Лечится строкой <key>SENTRY_DSN</key><string>$(SENTRY_DSN)</string> \
            в TripTrack/Info.plist, рядом с API_BASE_URL.
            """)
        XCTAssertFalse(value?.contains("$(") ?? false,
                       "подстановка не раскрылась — переменной нет ни в одном xcconfig")
    }

    /// И это ровно то значение, которое назвал `Local.xcconfig` для текущей
    /// конфигурации (тесты гоняются в Debug).
    func testTheValueComesFromLocalXcconfigAndNotFromNowhere() throws {
        let info = try builtAppInfoPlist()
        let value = info["SENTRY_DSN"] as? String ?? ""

        let root = UnitGuard.repoRoot()
        let xcconfig = root.appendingPathComponent("Local.xcconfig")
        guard let text = try? String(contentsOf: xcconfig, encoding: .utf8) else {
            throw XCTSkip("Local.xcconfig нет — это нормально на чистой машине")
        }
        // Разбор по ПЕРВОМУ `=` здесь не годится: он стоит внутри `[config=…]`.
        let key = "SENTRY_DSN[config=Debug]"
        let declared = text
            .split(separator: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix(key) else { return nil }
                let rest = trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
                guard rest.hasPrefix("=") else { return nil }
                return String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            .first
        guard let declared else {
            throw XCTSkip("Local.xcconfig не задаёт SENTRY_DSN для Debug")
        }
        // `$()` в самом значении — приём из шаблона, чтобы `//` в `https://`
        // не съелся комментарием xcconfig; артефакт его уже не несёт.
        XCTAssertEqual(value, declared.replacingOccurrences(of: "$()", with: ""),
                       "значение из xcconfig обязано доехать до артефакта дословно")
    }

    /// Шаблон в репозитории тоже обязан нести ключ: артефакт собирается из
    /// него, а рабочая копия на машине владельца может расходиться с гитом.
    func testTheTemplateInTheRepositoryDeclaresTheKey() throws {
        let root = UnitGuard.repoRoot()
        let template = root.appendingPathComponent("TripTrack/Info.plist")
        let text = try String(contentsOf: template, encoding: .utf8)
        XCTAssertTrue(text.contains("<key>SENTRY_DSN</key>"),
                      "шаблон Info.plist обязан объявлять SENTRY_DSN")
        XCTAssertTrue(text.contains("$(SENTRY_DSN)"),
                      "и подставлять в него переменную сборки")
    }
}
