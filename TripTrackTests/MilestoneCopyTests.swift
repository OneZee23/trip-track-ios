import XCTest
import CoreLocation
@testable import TripTrack

/// Слова вехи: карточка печати обязана отвечать на «что это за кружок».
///
/// До этой правки у вехи не было ни одной строки во всём приложении —
/// `Discovery.title` ей не даётся (имя зависит от языка телефона, колонка в
/// базе — нет), и карточка показывала слово «ВЕХА» и дату. Здесь проверяется,
/// что заголовок собирается из КЛЮЧА, что ключ разбирается у всех десяти вех и
/// что в тексте нет ни одного числа с единицей.
@MainActor
final class MilestoneCopyTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        await RegionAtlas.shared.loadIfNeeded()
    }

    // MARK: - Разбор ключа

    func testKeyOfEveryMilestoneParsesBack() {
        for milestone in Milestone.allCases {
            // Ключ без хвоста — веха раз в жизни; с хвостом — регион, пара
            // стран или день.
            XCTAssertEqual(MilestoneCopy.milestone(ofKey: milestone.rawValue), milestone)
            XCTAssertEqual(
                MilestoneCopy.milestone(ofKey: "\(milestone.rawValue):RU-KDA"), milestone)
        }
        XCTAssertNil(MilestoneCopy.milestone(ofKey: "somethingFromTheFuture:2027-01-01"))
        XCTAssertNil(MilestoneCopy.milestone(ofKey: ""))
    }

    // MARK: - Заголовок

    func testEveryMilestoneHasAWordInEveryLanguage() {
        for milestone in Milestone.allCases {
            for lang in LanguageManager.Language.allCases {
                let title = AppStrings.milestoneTitle(lang, milestone)
                XCTAssertFalse(title.isEmpty, "\(milestone) на \(lang) пуста")
                XCTAssertFalse(title.contains("milestoneTitle"),
                               "\(milestone) на \(lang) отдала ключ вместо строки")
            }
        }
    }

    /// Единиц в тексте нет: порог высоты — две тысячи метров, и вписанные сюда
    /// «2000 м» врали бы на телефоне, который меряет в футах. Заголовок
    /// отвечает словами — «Высоко в горах».
    func testNoMilestoneTitleCarriesANumber() {
        for milestone in Milestone.allCases {
            for lang in LanguageManager.Language.allCases {
                let title = AppStrings.milestoneTitle(lang, milestone)
                XCTAssertNil(title.rangeOfCharacter(from: .decimalDigits),
                             "число в заголовке вехи \(milestone) (\(lang)): «\(title)»")
            }
        }
    }

    func testTitleComesFromTheKey() {
        XCTAssertEqual(MilestoneCopy.title(forKey: "firstRegion:RU-KDA", .ru),
                       AppStrings.milestoneTitle(.ru, .firstRegion))
        XCTAssertEqual(MilestoneCopy.title(forKey: "above2000", .en),
                       AppStrings.milestoneTitle(.en, .above2000))
        XCTAssertNil(MilestoneCopy.title(forKey: "unknownThing:2026-09-16", .ru),
                     "сырой ключ на экран не печатается")
    }

    // MARK: - Где это случилось

    func testFirstRegionCarriesTheRegionName() {
        XCTAssertEqual(MilestoneCopy.place(forKey: "firstRegion:RU-KDA", .ru), "Краснодарский край")
        XCTAssertEqual(MilestoneCopy.place(forKey: "firstRegion:RU-KDA", .en), "Krasnodar Krai")
        XCTAssertNil(MilestoneCopy.place(forKey: "firstRegion:XX-ZZZ", .ru),
                     "регион не из атласа — молчим, а не печатаем код")
    }

    func testBorderCarriesBothCountries() {
        XCTAssertEqual(MilestoneCopy.place(forKey: "countryBorder:GE-RU", .ru), "Грузия — Россия")
        XCTAssertEqual(MilestoneCopy.place(forKey: "countryBorder:GE-RU", .en), "Georgia — Russia")
    }

    /// У вех с ДНЁМ в хвосте места нет: дата и так напечатана строкой ниже, и
    /// «2026-09-16» под заголовком читалось бы как имя объекта.
    func testDayKeyedMilestonesHaveNoPlaceLine() {
        XCTAssertNil(MilestoneCopy.place(forKey: "easternmost:2026-09-16", .ru))
        XCTAssertNil(MilestoneCopy.place(forKey: "nightPass:2026-09-16", .en))
        XCTAssertNil(MilestoneCopy.place(forKey: "above2000", .ru))
    }

    // MARK: - VoiceOver

    func testSealLabelSaysWhichMilestoneItIs() {
        let milestone = Discovery(
            kind: .milestone, key: "firstRegion:RU-KDA", tripId: UUID(),
            coordinate: CLLocationCoordinate2D(latitude: 45, longitude: 39),
            foundAt: Date(), symbol: .region)
        let label = DiscoveryCopy.accessibility(for: milestone, .ru)
        XCTAssertTrue(label.contains(AppStrings.sealKind(.ru, kind: .milestone)))
        XCTAssertTrue(label.contains(AppStrings.milestoneTitle(.ru, .firstRegion)))
        XCTAssertTrue(label.contains("Краснодарский край"))

        // У безымянной загадки — «Загадка решена»: строка, которая до этой
        // правки была переведена на тринадцать языков и не звалась ниоткуда.
        let riddle = Discovery(
            kind: .riddle, key: "border:ubb6mvz", tripId: UUID(),
            coordinate: CLLocationCoordinate2D(latitude: 45, longitude: 39),
            foundAt: Date(), symbol: .border)
        XCTAssertTrue(DiscoveryCopy.accessibility(for: riddle, .ru)
            .contains(AppStrings.riddleSolvedTitle(.ru)))

        // А у загадки С ИМЕНЕМ говорится имя: «Загадка решена» рядом с ним
        // было бы шумом.
        let named = Discovery(
            kind: .riddle, key: "lighthouse:ubb6mvz", tripId: UUID(),
            coordinate: CLLocationCoordinate2D(latitude: 45, longitude: 39),
            foundAt: Date(), symbol: .lighthouse, title: "Геленджикский маяк")
        let namedLabel = DiscoveryCopy.accessibility(for: named, .ru)
        XCTAssertTrue(namedLabel.contains("Геленджикский маяк"))
        XCTAssertFalse(namedLabel.contains(AppStrings.riddleSolvedTitle(.ru)))
    }
}
