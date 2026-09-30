import XCTest
@testable import TripTrack

/// Чаевые обещают НИЧЕГО, и это сказано словами — требование Apple к донату и
/// то единственное, чем они отличаются от тарифа.
final class TipJarCopyTests: XCTestCase {

    // MARK: - Копия листа

    /// Единственное обещание листа — что обещаний нет.
    func testTipSheetSaysNothingIsUnlocked() {
        for lang in LanguageManager.Language.allCases {
            let body = AppStrings.tipsText(lang)
            XCTAssertFalse(body.isEmpty, "\(lang.rawValue): пустое объяснение")
            XCTAssertFalse(body.contains("{"), "\(lang.rawValue): токен не подставлен")
        }
        XCTAssertNotEqual(AppStrings.tipsText(.ru), AppStrings.tipsText(.de),
                          "немецкий остался английским")
    }

    /// Все восемь строк переведены. Ключ без строки откатывается на
    /// АНГЛИЙСКИЙ — то есть выглядит рабочим и молчит; ловится сравнением.
    func testEveryTipLineIsTranslated() {
        let lines: [(String, (LanguageManager.Language) -> String)] = [
            ("tipsEntry", AppStrings.tipsEntry),
            ("tipsTitle", AppStrings.tipsTitle),
            ("tipsText", AppStrings.tipsText),
            ("tipsCoffee", AppStrings.tipsCoffee),
            ("tipsMeal", AppStrings.tipsMeal),
            ("tipsFuel", AppStrings.tipsFuel),
            ("tipsThanks", AppStrings.tipsThanks),
            ("tipsThanksText", AppStrings.tipsThanksText),
        ]
        for (name, line) in lines {
            let en = line(.en)
            XCTAssertFalse(en.isEmpty, name)
            for lang in [LanguageManager.Language.ru, .de, .es, .fr, .it,
                         .pl, .id, .tr, .fil, .uk, .kk, .pt] {
                XCTAssertNotEqual(line(lang), en,
                                  "\(name): у \(lang.rawValue) строка осталась английской")
            }
        }
    }

    /// Прежние `tipTitle`/`tipSubtitle`/`tipThanks` ПЕРЕИМЕНОВАНЫ, а не
    /// продублированы: имена по ключу дизайна выходят обманчиво похожими
    /// (`tipsTitle` против `tipTitle`), и держать обе пары значило бы держать
    /// тринадцать языков мёртвой копии. Сторож читает таблицы.
    func testTheOldTipKeysAreGoneFromEveryTable() {
        let root = UnitGuard.repoRoot()
            .appendingPathComponent("TripTrack/Localization/Translations")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        XCTAssertFalse(files.isEmpty, "таблиц рядом с тестом нет — сторожу нечего читать")
        for name in files where name.hasSuffix(".swift") {
            let text = (try? String(contentsOf: root.appendingPathComponent(name),
                                    encoding: .utf8)) ?? ""
            for old in ["\"tipTitle\"", "\"tipSubtitle\"", "\"tipThanks\""] {
                XCTAssertFalse(text.contains(old), "\(name) держит мёртвый ключ \(old)")
            }
        }
    }

    // MARK: - Видимость входа

    /// Чаевые видны и ПОДПИСЧИКУ: это решение владельца, а не забытый гейт
    /// (спека §11 — «видны всем с витриной, и с PRO, и без»). Прячет их только
    /// витрина, которая платного не продаёт.
    func testTipsAreShownToSubscribersToo() {
        XCTAssertTrue(TipEntry.isVisible(status: .active(until: Date())))
        XCTAssertTrue(TipEntry.isVisible(status: .trial(until: Date())))
        XCTAssertTrue(TipEntry.isVisible(status: .none))
        XCTAssertTrue(TipEntry.isVisible(status: .expired(on: Date())))
        XCTAssertTrue(TipEntry.isVisible(status: .grace))
        XCTAssertTrue(TipEntry.isVisible(status: .pending))
        XCTAssertTrue(TipEntry.isVisible(status: .proWithoutStore(until: nil)),
                      "купил на другой витрине — сказать спасибо всё равно можно")
        XCTAssertFalse(TipEntry.isVisible(status: .hiddenStorefront),
                       "витрина не продаёт — ни подписки, ни чаевых")
    }

    /// Ровно ОДИН статус прячет строку. Без этой половины проверка проходила
    /// бы и на `isVisible`, прибитом к `true`.
    func testExactlyOneStatusHidesTheTips() {
        let hidden = Self.everyStatus.filter { !TipEntry.isVisible(status: $0) }
        XCTAssertEqual(hidden, [.hiddenStorefront])
    }

    // MARK: - Пометка «вписана рукой» (состояние 39)

    /// **На карточках только карандаш без слов, слова — на экране поездки.**
    ///
    /// Сторожится ЧТЕНИЕМ ИСХОДНИКОВ, а не константой: константа, которую сам
    /// вид не читает, назавтра разойдётся с ним и промолчит. Правило же
    /// конкретное — `manualTripBadge` на карточке уходит ТОЛЬКО в
    /// `accessibilityLabel` (строка карточки тесная, и слово «Вписана рукой» в
    /// ней встало бы вместо даты), а на экране поездки — в видимый `Label`.
    func testHandEnteredMarkIsIconOnCardsAndWordsOnTheTripScreen() {
        let root = UnitGuard.repoRoot()

        for card in ["TripTrack/Views/Profile/ProfileTripCardView.swift",
                     "TripTrack/Views/Feed/SocialFeedCardView.swift"] {
            let text = Self.source(root, card)
            guard text.contains("manualTripBadge") else { continue }
            for line in text.split(separator: "\n") where line.contains("manualTripBadge") {
                XCTAssertTrue(
                    line.contains("accessibilityLabel"),
                    "\(card): «Вписана рукой» попало в ВИДИМЫЙ текст карточки — "
                    + "строка и так тесная. Строка: \(line.trimmingCharacters(in: .whitespaces))")
            }
        }

        let detail = Self.source(root, "TripTrack/Views/Trips/TripDetailView.swift")
        XCTAssertTrue(detail.contains("manualTripBadge"),
                      "экран поездки потерял пометку словами — на нём места хватает, "
                      + "и «записана треком» это умолчание, а не факт")
        XCTAssertTrue(detail.contains("Label(AppStrings.manualTripBadge"),
                      "на экране поездки пометка обязана быть ВИДИМОЙ, а не только для озвучки")
    }

    // MARK: -

    private static func source(_ root: URL, _ path: String) -> String {
        (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
    }

    private static let everyStatus: [ProStatus] = [
        .none, .trial(until: nil), .active(until: nil), .expired(on: nil),
        .grace, .pending, .hiddenStorefront, .proWithoutStore(until: nil)
    ]

    // MARK: - Где стоит вход

    /// Вход в чаевые — РОВНО ОДИН, и он в листе настроек, рядом с автором.
    ///
    /// До 0.8.4 строка жила в подвале «Я», и первая редакция 0.8.4 забыла её в
    /// одной из ДВУХ раскладок профиля: человек без единой поездки видел
    /// раздел «Подписка», но не видел «Поддержать». Переезд в карточку автора
    /// (решение владельца 30 сен 2026) убрал саму возможность такой ошибки —
    /// лист настроек один. Сторож держит это буквально: появится второй вход,
    /// и тест скажет, где именно.
    ///
    /// Поведением не задать: обе прежние ветки были разметкой одного экрана, и
    /// различало их состояние библиотеки.
    func testTipEntryLivesOnlyInSettingsAndIsGated() throws {
        let root = UnitGuard.repoRoot()

        let settings = try String(
            contentsOf: root.appendingPathComponent(
                "TripTrack/Views/Profile/ProfileSettingsSheet.swift"),
            encoding: .utf8)
        XCTAssertTrue(settings.contains("settings_support"),
                      "вход в чаевые пропал из листа настроек")
        XCTAssertTrue(settings.contains("TipEntry.isVisible(status:"),
                      "вход в чаевые не закрыт правилом `TipEntry.isVisible` — "
                      + "на витрине, которая платного не продаёт, он покажет "
                      + "кнопку, которая не может сработать")

        let profile = try String(
            contentsOf: root.appendingPathComponent(
                "TripTrack/Views/Profile/ProfileView.swift"),
            encoding: .utf8)
        XCTAssertFalse(profile.contains("TipJarSheet"),
                       "чаевые вернулись в «Я» вторым входом — их место в листе "
                       + "настроек, рядом с автором")
    }

}
