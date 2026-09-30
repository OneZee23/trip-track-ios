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
        XCTAssertTrue(ProfileSupportRow.isVisible(status: .active(until: Date())))
        XCTAssertTrue(ProfileSupportRow.isVisible(status: .trial(until: Date())))
        XCTAssertTrue(ProfileSupportRow.isVisible(status: .none))
        XCTAssertTrue(ProfileSupportRow.isVisible(status: .expired(on: Date())))
        XCTAssertTrue(ProfileSupportRow.isVisible(status: .grace))
        XCTAssertTrue(ProfileSupportRow.isVisible(status: .pending))
        XCTAssertTrue(ProfileSupportRow.isVisible(status: .proWithoutStore(until: nil)),
                      "купил на другой витрине — сказать спасибо всё равно можно")
        XCTAssertFalse(ProfileSupportRow.isVisible(status: .hiddenStorefront),
                       "витрина не продаёт — ни подписки, ни чаевых")
    }

    /// Ровно ОДИН статус прячет строку. Без этой половины проверка проходила
    /// бы и на `isVisible`, прибитом к `true`.
    func testExactlyOneStatusHidesTheTips() {
        let hidden = Self.everyStatus.filter { !ProfileSupportRow.isVisible(status: $0) }
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

    // MARK: - Где строка стоит

    /// Строка «Поддержать» есть в КАЖДОЙ раскладке профиля.
    ///
    /// У «Я» два хвоста: своя разметка у «поездок ещё нет» и своя у обычного
    /// профиля. Первая редакция 0.8.4 добавила строку только во вторую, и
    /// человек без единой поездки видел раздел «Подписка», но не видел
    /// «Поддержать» — при том что он-то и есть адресат: поддержать работу
    /// хочется раньше, чем накопится история.
    ///
    /// Инвариант выражен через КЛУБЫ, а не числом: раздел клубов рисуется в
    /// обеих ветках и никуда не денется, поэтому «строка поддержки стоит
    /// столько же раз, сколько клубы» и значит «во всех раскладках». Числом
    /// было бы хрупко — ветки профиля ещё будут добавляться.
    ///
    /// Поведением это не задать: обе ветки — разметка одного экрана, и
    /// различает их состояние библиотеки. Поймал это снимочный тур
    /// `PlusShotTests` (он идёт по чистой установке), но он не входит в
    /// обычный прогон — отсюда сторож здесь.
    func testSupportRowAppearsInEveryProfileLayout() throws {
        let url = UnitGuard.repoRoot()
            .appendingPathComponent("TripTrack/Views/Profile/ProfileView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        func callSites(_ name: String) -> Int {
            source.components(separatedBy: "\n")
                .filter { line in
                    let t = line.trimmingCharacters(in: .whitespaces)
                    return t == "\(name)()" || t.hasPrefix("\(name)(c)")
                }
                .count
        }

        let clubs = callSites("clubsSection")
        let support = callSites("supportRow")
        XCTAssertGreaterThan(clubs, 0, "не нашёл вызовов clubsSection — тест смотрит не туда")
        XCTAssertEqual(support, clubs,
                       "раскладок профиля \(clubs), а строка «Поддержать» стоит в \(support): "
                       + "в какой-то ветке её забыли")
    }

}
