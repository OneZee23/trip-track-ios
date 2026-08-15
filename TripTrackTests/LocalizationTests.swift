import XCTest
@testable import TripTrack

/// The seven-language layer added in 0.6.1.
///
/// The thing these guard against is silent: a key renamed in `AppStrings` and
/// not renamed in `Translations+XX.swift` does not fail to compile — the
/// lookup just misses and the screen quietly comes out English. Nothing else
/// in the build notices.
final class LocalizationTests: XCTestCase {

    /// Languages whose sheets are finished. A language is added here the moment
    /// its table is complete — until then it ships with an empty table and
    /// falls back to English, which is correct but is not what these assert.
    private var completeLanguages: [(LanguageManager.Language, [String: String])] {
        [(.de, Translations.de), (.es, Translations.es), (.fr, Translations.fr),
         (.it, Translations.it), (.pl, Translations.pl), (.tr, Translations.tr),
         (.id, Translations.id), (.uk, Translations.uk), (.pt, Translations.pt),
         (.kk, Translations.kk), (.fil, Translations.fil)]
    }

    /// Sheets still being written. Empty now that all thirteen are done — kept
    /// because the next language added starts here, and the two tests below
    /// spell out the difference between "short" and "wrong".
    private var inProgressLanguages: [(LanguageManager.Language, [String: String])] {
        []
    }

    // MARK: - Tables

    /// All five tables are generated from the same key list, so any difference
    /// between them means one was hand-edited and drifted.
    func testEveryFinishedTableHasTheSameKeys() {
        let reference = Set(Translations.de.keys)
        XCTAssertFalse(reference.isEmpty, "German table is empty — is it wired up?")
        for (lang, table) in completeLanguages {
            let keys = Set(table.keys)
            XCTAssertEqual(
                keys, reference,
                """
                \(lang.rawValue) differs from de by \
                \(keys.symmetricDifference(reference).sorted().prefix(10))
                """
            )
        }
    }

    /// An unfinished sheet is allowed to be short — it is not allowed to carry
    /// a key that does not exist, which is how a typo hides for a release.
    func testUnfinishedTablesCarryOnlyRealKeys() {
        let reference = Set(Translations.de.keys)
        for (lang, table) in inProgressLanguages {
            let unknown = Set(table.keys).subtracting(reference)
            XCTAssertTrue(
                unknown.isEmpty,
                "\(lang.rawValue) has keys nothing reads: \(unknown.sorted().prefix(10))"
            )
        }
    }

    func testNoTranslationIsEmptyOrAKeyEchoedBack() {
        for (lang, table) in completeLanguages + inProgressLanguages {
            for (key, value) in table {
                XCTAssertFalse(
                    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(lang.rawValue).\(key) is empty"
                )
                // A value equal to its key means the generator wrote the
                // identifier out instead of the translation — but only when
                // the key is camelCase. Single-word keys like `km` and `m`
                // are units that legitimately read the same everywhere.
                if key.contains(where: \.isUppercase) {
                    XCTAssertNotEqual(value, key, "\(lang.rawValue).\(key) is the key itself")
                }
            }
        }
    }

    /// `tr` must reach the table, not fall through to English. If the wiring
    /// breaks, every one of these silently returns the English string.
    func testTranslationsAreActuallyReached() {
        XCTAssertEqual(AppStrings.cancel(.de), "Abbrechen")
        XCTAssertEqual(AppStrings.cancel(.es), "Cancelar")
        XCTAssertEqual(AppStrings.cancel(.fr), "Annuler")
        XCTAssertEqual(AppStrings.cancel(.it), "Annulla")
        XCTAssertEqual(AppStrings.cancel(.pl), "Anuluj")
    }

    /// A key with no row falls back to English rather than showing the key.
    func testMissingKeyFallsBackToEnglish() {
        XCTAssertEqual(
            AppStrings.tr(.de, "no-such-key-exists", ru: "русский", en: "english"),
            "english"
        )
    }

    // MARK: - Plurals

    func testRussianPluralForms() {
        XCTAssertEqual(AppStrings.nounTrips(.ru, 1), "поездка")
        XCTAssertEqual(AppStrings.nounTrips(.ru, 2), "поездки")
        XCTAssertEqual(AppStrings.nounTrips(.ru, 5), "поездок")
        XCTAssertEqual(AppStrings.nounTrips(.ru, 11), "поездок")
        XCTAssertEqual(AppStrings.nounTrips(.ru, 21), "поездка")
        XCTAssertEqual(AppStrings.nounTrips(.ru, 22), "поездки")
        XCTAssertEqual(AppStrings.nounTrips(.ru, 111), "поездок")
    }

    /// Polish is not Russian: 21 takes the genitive plural, not the singular.
    /// This is the one Slavic rule that is easy to get wrong by copying.
    func testPolishPluralDivergesFromRussianAtTwentyOne() {
        XCTAssertEqual(AppStrings.pluralForm(1, .pl), .one)
        XCTAssertEqual(AppStrings.pluralForm(2, .pl), .few)
        XCTAssertEqual(AppStrings.pluralForm(5, .pl), .many)
        XCTAssertEqual(AppStrings.pluralForm(21, .pl), .many)
        XCTAssertEqual(AppStrings.pluralForm(21, .ru), .one)
        XCTAssertEqual(AppStrings.pluralForm(22, .pl), .few)
    }

    /// French counts zero with the singular.
    func testFrenchTreatsZeroAsSingular() {
        XCTAssertEqual(AppStrings.pluralForm(0, .fr), .one)
        XCTAssertEqual(AppStrings.nounTrips(.fr, 0), "trajet")
        XCTAssertEqual(AppStrings.nounTrips(.fr, 2), "trajets")
        XCTAssertEqual(AppStrings.pluralForm(0, .en), .many)
    }

    func testTwoFormLanguagesFallBackToManyWhenFewIsOmitted() {
        XCTAssertEqual(AppStrings.plural(.de, 3, one: "Fahrt", many: "Fahrten"), "Fahrten")
        XCTAssertEqual(AppStrings.plural(.de, 1, one: "Fahrt", many: "Fahrten"), "Fahrt")
    }

    // MARK: - Language

    /// `en`/`ru` are persisted in UserDefaults and read by the widget and the
    /// Live Activity. Renaming a case would silently reset everyone's choice.
    func testRawValuesAreStableIsoCodes() {
        XCTAssertEqual(
            Set(LanguageManager.Language.allCases.map(\.rawValue)),
            ["en", "ru", "de", "es", "fr", "it", "pl", "id", "tr", "fil", "uk", "kk", "pt"]
        )
    }

    func testDisplayOrderCoversEveryLanguageExactlyOnce() {
        XCTAssertEqual(
            Set(LanguageManager.Language.displayOrder),
            Set(LanguageManager.Language.allCases)
        )
        XCTAssertEqual(
            LanguageManager.Language.displayOrder.count,
            LanguageManager.Language.allCases.count
        )
        XCTAssertEqual(LanguageManager.Language.displayOrder.first, .ru, "canon leads with RU")
    }

    func testDetectionReadsTheLanguageSubtag() {
        XCTAssertEqual(LanguageManager.Language.detect(from: ["de-DE"]), .de)
        XCTAssertEqual(LanguageManager.Language.detect(from: ["pl-PL", "en-US"]), .pl)
        XCTAssertEqual(LanguageManager.Language.detect(from: ["zh-Hans-CN"]), .en)
        XCTAssertEqual(LanguageManager.Language.detect(from: []), .en)
    }

    /// A phone with no supported language FIRST should still land on a
    /// supported one it lists second, rather than dropping to English.
    func testDetectionWalksThePreferenceList() {
        // Thai is not one of ours, so detection has to keep walking. (It used
        // to be Portuguese here — which stopped proving anything the moment
        // Portuguese became a supported language.)
        XCTAssertEqual(LanguageManager.Language.detect(from: ["th-TH", "es-ES"]), .es)
    }

    func testEveryLanguageHasALocaleAndAnEndonym() {
        for lang in LanguageManager.Language.allCases {
            // `fil` and `pt` are three- and two-letter subtags with a region
            // attached («fil_PH», «pt_BR»), so compare the language code the
            // locale reports rather than slicing the identifier.
            XCTAssertEqual(lang.locale.language.languageCode?.identifier, lang.rawValue)
            XCTAssertFalse(lang.endonym.isEmpty)
            XCTAssertEqual(lang.badge.count, 2, "\(lang.rawValue) badge must be two characters")
        }
    }

    // MARK: - Formatting

    /// Two of the thirteen write tenths with a dot — English and Filipino.
    /// This used to be «English is the only one», which is exactly the kind of
    /// rule that quietly stops being true when a language is added; the
    /// separator is asked of the locale now, and this pins the answer.
    func testDecimalSeparator() {
        let dotted: Set<LanguageManager.Language> = [.en, .fil]
        for lang in LanguageManager.Language.allCases {
            XCTAssertEqual(
                AppStrings.decimalSeparator(lang),
                dotted.contains(lang) ? "." : ",",
                "wrong decimal separator for \(lang.rawValue)"
            )
        }
    }

    func testDateFormattersExistForEveryLanguage() {
        let table = LocalizedDateFormatter.patterns("d MMM yyyy")
        for lang in LanguageManager.Language.allCases {
            XCTAssertNotNil(table[lang], "no formatter for \(lang.rawValue)")
            XCTAssertEqual(table[lang]?.locale, lang.locale)
        }
    }

    /// The Live Activity cannot see `AppStrings`, so its strings live in the
    /// shared target and key off the raw code — including the fallback.
    func testLiveActivityStringsCoverEveryLanguage() {
        for lang in LanguageManager.Language.allCases {
            XCTAssertFalse(LiveActivityStrings.paused(lang.rawValue).isEmpty)
            XCTAssertFalse(LiveActivityStrings.speedCaption(lang.rawValue).isEmpty)
        }
        XCTAssertEqual(LiveActivityStrings.paused("de"), "Pausiert")
        XCTAssertEqual(LiveActivityStrings.paused("xx"), LiveActivityStrings.paused("en"))
    }

    // MARK: - Content keys
    //
    // Badges, ranks and clubs build their key at runtime («badge.\(id).title»),
    // so the generator cannot scrape them out of the source the way it does the
    // literal ones. These are what stops a renamed badge id from quietly
    // reverting that badge to English.

    func testEveryBadgeHasATitleAndDescriptionRow() {
        for badge in Badge.all {
            for suffix in ["title", "desc"] {
                let key = "badge.\(badge.id).\(suffix)"
                XCTAssertNotNil(Translations.de[key], "no German row for \(key)")
                XCTAssertNotNil(Translations.pl[key], "no Polish row for \(key)")
            }
        }
    }

    func testEveryClubHasNameAndBlurbRows() {
        for club in Club.all {
            XCTAssertNotNil(Translations.fr["club.\(club.id).name"])
            XCTAssertNotNil(Translations.fr["club.\(club.id).blurb"])
        }
    }

    func testEveryContentEnumCaseHasARow() {
        func check<T: CaseIterable>(_ prefix: String, _ type: T.Type, key: (T) -> String) {
            for value in T.allCases {
                let k = "\(prefix).\(key(value))"
                XCTAssertNotNil(Translations.es[k], "no Spanish row for \(k)")
                XCTAssertNotNil(Translations.it[k], "no Italian row for \(k)")
            }
        }
        check("badgeCategory", BadgeCategory.self) { $0.rawValue }
        check("badgeRarity", BadgeRarity.self) { "\($0)" }
        check("driverRank", DriverRank.self) { "\($0)" }
        check("vehicleSticker", VehicleSticker.self) { "\($0)" }
        check("roadRarity", RoadRarity.self) { "\($0)" }
        check("roadLevel", RoadLevel.self) { "\($0)" }
        check("zoneStatus", ZoneStatus.self) { "\($0)" }
    }

    /// Badge copy actually reaches the table rather than falling back.
    func testBadgeTitleIsTranslated() {
        let first = Badge.all.first { $0.id == "first_trip" }
        XCTAssertEqual(first?.title(.de), "Erste Fahrt")
        XCTAssertEqual(first?.title(.pl), "Pierwsza trasa")
    }

    // MARK: - Turkish casing

    /// The dotless-i trap: plain `uppercased()` turns «i» into «I», but Turkish
    /// writes «İ». Section headers in this app are upper-cased in code, so
    /// without the locale «BURADAKİ GEZİLER» ships as «BURADAKI GEZILER».
    func testTurkishCasingKeepsTheDottedI() {
        XCTAssertEqual("i".uppercased(.tr), "İ")
        XCTAssertEqual("I".lowercased(.tr), "ı")
        XCTAssertEqual("i".uppercased(.en), "I")
        XCTAssertEqual(
            AppStrings.mapTripsSection(.tr, count: 3).uppercased(.tr),
            AppStrings.mapTripsSection(.tr, count: 3).uppercased(with: LanguageManager.Language.tr.locale)
        )
    }

    /// Indonesian has no plural inflection: one word covers every count.
    func testIndonesianHasASingleForm() {
        XCTAssertEqual(AppStrings.nounTrips(.id, 1), AppStrings.nounTrips(.id, 5))
        XCTAssertEqual(AppStrings.nounTrips(.id, 0), "perjalanan")
    }

    /// Ukrainian follows the same three-form rule as Russian.
    func testUkrainianPluralMatchesTheSlavicRule() {
        XCTAssertEqual(AppStrings.pluralForm(1, .uk), .one)
        XCTAssertEqual(AppStrings.pluralForm(3, .uk), .few)
        XCTAssertEqual(AppStrings.pluralForm(11, .uk), .many)
        XCTAssertEqual(AppStrings.pluralForm(21, .uk), .one)
    }
}
