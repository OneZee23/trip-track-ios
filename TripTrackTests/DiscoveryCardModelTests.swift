import XCTest
import CoreLocation
@testable import TripTrack

/// Карточка находки: что она показывает у каждого вида и при каком состоянии
/// облака.
///
/// Чистой моделью, а не снимком экрана: правил здесь четыре, и все четыре
/// молчаливые — счётчик первооткрывателей без Cloud Sync (спрашивать было
/// нечем), `finders == nil` как «не спрашивали» вместо нуля, секрет без
/// истории и кнопка «На карте», которая на самой карте была бы обещанием без
/// содержания. Каждое чинится одной строкой в `body` и ломается там же
/// незаметно.
///
/// Полей у класса нет намеренно — фикстуры собираются в каждом тесте (см.
/// `JournalBuilderTests`: поле, пережившее тест, роняет чужой класс через
/// полчаса прогона).
final class DiscoveryCardModelTests: XCTestCase {

    // MARK: - Фикстуры

    private static let day = DateComponents(
        calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC"),
        year: 2026, month: 9, day: 12, hour: 12).date!

    private func find(
        kind: DiscoveryKind,
        key: String,
        title: String? = nil,
        story: String? = nil,
        finders: Int? = nil,
        firstFinderName: String? = nil
    ) -> Discovery {
        Discovery(
            kind: kind, key: key, tripId: UUID(),
            coordinate: CLLocationCoordinate2D(latitude: 45.03, longitude: 38.97),
            foundAt: Self.day, symbol: .lighthouse,
            title: title, story: story, verified: false,
            finders: finders, firstFinderName: firstFinderName,
            firstFinderAt: finders == nil ? nil : Self.day, rarity: nil)
    }

    private func make(
        _ discovery: Discovery, cloudSync: Bool = true, showsOnMap: Bool = false,
        lang: LanguageManager.Language = .ru
    ) -> DiscoveryCardModel {
        DiscoveryCardModel.make(
            discovery: discovery, cloudSync: cloudSync, lang: lang, showsOnMap: showsOnMap)
    }

    // MARK: - Виды

    /// У секрета карточка несёт имя и историю — и ни круга, ни «решена
    /// проездом»: они про загадку.
    func testSecretShowsTitleAndStory() {
        let model = make(find(
            kind: .secret, key: "s1", title: "Комсомольский", story: "Район, который"))
        XCTAssertEqual(model.title, "Комсомольский")
        XCTAssertEqual(model.story, "Район, который")
        XCTAssertNil(model.circle)
        XCTAssertNil(model.solvedLine)
        XCTAssertNil(model.detail)
        XCTAssertFalse(model.dateLine.isEmpty)
    }

    /// Загадка: строка про то, что искалось, круг на мини-карте и дата
    /// проезда. Круг — вокруг САМОЙ загадки: радиус подсказки не хранится, а
    /// точка решённой известна точно.
    func testRiddleCarriesLineCircleAndSolvedDate() {
        let model = make(find(kind: .riddle, key: "lighthouse:u0h2w1q", title: "Мыс"))
        XCTAssertEqual(model.title, "Мыс")
        XCTAssertEqual(model.detail, AppStrings.riddleLine(.ru, type: .lighthouse))
        XCTAssertEqual(model.circle?.radiusMetres, RiddleHint.minRadiusMetres)
        XCTAssertEqual(model.circle?.centre.latitude, 45.03)
        XCTAssertEqual(model.solvedLine, AppStrings.cardSolvedOn(.ru, date: "12.09"))
        XCTAssertNil(model.story)
    }

    /// У безымянной загадки бандла заголовок собирается словами, а не остаётся
    /// пустым: одна дата не отвечает ни на что.
    func testRiddleWithoutNameStillHasATitle() {
        let model = make(find(kind: .riddle, key: "bridge:u0h2w1q"))
        XCTAssertEqual(model.title, AppStrings.riddleSolvedTitle(.ru))
    }

    /// Веха: заголовок и место — из КЛЮЧА, потому что в базе у неё имени нет
    /// вовсе (оно зависит от языка телефона).
    func testMilestoneTitleAndPlaceComeFromTheKey() {
        let model = make(find(kind: .milestone, key: "firstRegion:RU-KDA"))
        XCTAssertEqual(model.title, AppStrings.milestoneTitle(.ru, .firstRegion))
        XCTAssertEqual(model.detail, MilestoneCopy.place(forKey: "firstRegion:RU-KDA", .ru))
        XCTAssertNil(model.circle)
        XCTAssertNil(model.solvedLine)
        XCTAssertNil(model.story)
    }

    /// Веха с незнакомым ключом (чужая версия, будущая веха) остаётся без
    /// заголовка — сырой ключ на карточке не печатается.
    func testUnknownMilestoneKeyLeavesTheTitleEmpty() {
        XCTAssertNil(make(find(kind: .milestone, key: "teleport:XX")).title)
    }

    // MARK: - Счётчик первооткрывателей

    func testFindersLineNeedsBothCloudSyncAndACount() {
        let counted = find(kind: .secret, key: "s1", title: "Т", finders: 7,
                           firstFinderName: "Илья")
        XCTAssertNotNil(make(counted, cloudSync: true).findersLine)
        XCTAssertNil(make(counted, cloudSync: false).findersLine,
                     "без облака счётчика не существует — спрашивать было нечем")
        XCTAssertNil(make(find(kind: .secret, key: "s1", title: "Т"), cloudSync: true)
            .findersLine, "`finders == nil` — это «не спрашивали», а не ноль")
    }

    /// Профиль первого закрыт — он «кто-то», а не пустое место.
    func testFirstFinderWithoutANameIsSomeone() {
        let model = make(find(kind: .secret, key: "s1", title: "Т", finders: 3))
        XCTAssertEqual(
            model.findersLine, AppStrings.cardFoundBy(.ru, count: 3,
                                                      name: AppStrings.cardFirstSomeone(.ru)))
        XCTAssertTrue(model.findersLine?.contains("кто-то") == true)
    }

    /// Счётное слово — через `nounPeople`, а не `if .ru`: 1/2/5 в русском
    /// берут три разные формы.
    func testRussianCountedNounTakesThreeForms() {
        XCTAssertEqual(AppStrings.cardFoundBy(.ru, count: 1, name: "И"),
                       "нашли 1 человек · первым — И")
        XCTAssertEqual(AppStrings.cardFoundBy(.ru, count: 2, name: "И"),
                       "нашли 2 человека · первым — И")
        XCTAssertEqual(AppStrings.cardFoundBy(.ru, count: 5, name: "И"),
                       "нашли 5 человек · первым — И")
    }

    /// Токены подставляются во ВСЕХ тринадцати: живая интерполяция внутри
    /// `tr` до одиннадцати таблиц не доезжает, и потерю числа заметить нечем.
    func testEveryLanguageSubstitutesBothTokens() {
        for lang in LanguageManager.Language.allCases {
            let line = AppStrings.cardFoundBy(lang, count: 4, name: "Ann")
            XCTAssertTrue(line.contains("4"), "\(lang.rawValue): число пропало")
            XCTAssertTrue(line.contains("Ann"), "\(lang.rawValue): имя пропало")
            XCTAssertFalse(line.contains("{"), "\(lang.rawValue): токен остался сырым")
            let solved = AppStrings.cardSolvedOn(lang, date: "12.09")
            XCTAssertTrue(solved.contains("12.09"), "\(lang.rawValue): дата пропала")
            XCTAssertFalse(solved.contains("{"), "\(lang.rawValue): токен остался сырым")
        }
    }

    // MARK: - «На карте»

    /// Кнопки нет, пока её не попросили: карточка, открытая ПЕЧАТЬЮ НА КАРТЕ,
    /// вела бы человека туда, где он уже стоит.
    func testOnMapButtonOnlyWhenAsked() {
        let secret = find(kind: .secret, key: "s1", title: "Т")
        XCTAssertFalse(make(secret).showsOnMap)
        XCTAssertTrue(make(secret, showsOnMap: true).showsOnMap)
    }

    // MARK: - История секрета

    /// В Debug секрет без истории показывает заглушку — иначе карточку до
    /// каталога волны 3 не увидеть вовсе; в проде её нет.
    func testSecretWithoutAStory() {
        let model = make(find(kind: .secret, key: "s1", title: "Т"))
        #if DEBUG
        XCTAssertEqual(model.story, AppStrings.cardStoryPending(.ru))
        #else
        XCTAssertNil(model.story)
        #endif
        XCTAssertEqual(model.title, "Т")
    }

    /// Заглушка — только у секрета: у загадки и вехи истории не бывает по
    /// построению, и «появится с обновлением» было бы обещанием, которого
    /// никто не давал.
    func testStoryPlaceholderNeverLeaksToRiddlesOrMilestones() {
        XCTAssertNil(make(find(kind: .riddle, key: "pass:u0")).story)
        XCTAssertNil(make(find(kind: .milestone, key: "above2000")).story)
    }

    /// Пустая строка с сервера — это отсутствие истории, а не история из
    /// пробелов.
    func testEmptyStoryIsTreatedAsNoStory() {
        let model = make(find(kind: .riddle, key: "pass:u0", story: ""))
        XCTAssertNil(model.story)
    }

    // MARK: - Язык

    /// Вид подписан словом того же языка, что и всё остальное на карточке.
    func testKindLabelFollowsTheLanguage() {
        let secret = find(kind: .secret, key: "s1", title: "Т")
        XCTAssertEqual(make(secret, lang: .en).kindLabel, AppStrings.sealKind(.en, kind: .secret))
        XCTAssertEqual(make(secret, lang: .ru).kindLabel, AppStrings.sealKind(.ru, kind: .secret))
    }
}
