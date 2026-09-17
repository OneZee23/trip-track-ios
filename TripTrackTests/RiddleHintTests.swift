import XCTest
import CoreLocation
import MapKit
@testable import TripTrack

/// Круг подсказки: сколько их, какого радиуса и где его середина.
///
/// Всё три вопроса — чистыми функциями, потому что проверить их на экране
/// нельзя: круг рисуется поверх тумана в масштабе страны, и «сместился ли
/// центр на четверть радиуса» глазами не различить. А цена ошибки — прицел:
/// круг, чья середина и есть загадка, выдаёт точку любому, кто увидел его
/// дважды.
final class RiddleHintTests: XCTestCase {

    // MARK: - Фикстуры

    private func riddle(
        _ id: String, _ type: RiddleType = .lighthouse, lat: Double, lon: Double
    ) -> Riddle {
        Riddle(id: id, type: type,
               coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
               name: id)
    }

    /// Пустой слой: прогонов нет, значит `roadsWithin50km == 0` и радиус
    /// максимальный. Ровно то, что нужно проверке смещения.
    private let emptyLayer = RevealedLayer.empty

    private func layer(runs: [[(Double, Double)]]) -> RevealedLayer {
        RevealedLayer.build(
            runs: runs.map { $0.map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) } },
            cellCount: 0, atlas: nil)
    }

    // MARK: - Радиус

    func testRadiusFollowsTheDensityFormula() {
        // 5 + 25 · (1 − roads/200) километров, зажато в 5…30.
        XCTAssertEqual(RiddleHint.radiusMetres(roadsWithin50km: 0), 30_000, accuracy: 1)
        XCTAssertEqual(RiddleHint.radiusMetres(roadsWithin50km: 100), 17_500, accuracy: 1)
        XCTAssertEqual(RiddleHint.radiusMetres(roadsWithin50km: 40), 25_000, accuracy: 1)
        XCTAssertEqual(RiddleHint.radiusMetres(roadsWithin50km: 200), 5_000, accuracy: 1)
    }

    func testRadiusIsClampedAtBothEnds() {
        XCTAssertEqual(RiddleHint.radiusMetres(roadsWithin50km: 10_000), 5_000, accuracy: 1,
                       "город с тысячами прогонов не уводит круг ниже пяти километров")
        XCTAssertEqual(RiddleHint.radiusMetres(roadsWithin50km: -5), 30_000, accuracy: 1,
                       "отрицательного числа прогонов не бывает, но падать на нём нельзя")
    }

    /// Прогоны считаются по коробкам, и пятьдесят километров — это пятьдесят
    /// километров: кусок дороги под Ростовом не уплотняет круг под Сочи.
    func testOnlyRunsWithinFiftyKilometresCount() {
        let near = layer(runs: [[(45.00, 39.00), (45.05, 39.05)]])
        let far = layer(runs: [[(50.00, 39.00), (50.05, 39.05)]])
        let point = CLLocationCoordinate2D(latitude: 45, longitude: 39)

        XCTAssertEqual(RiddleHint.openRunsWithin50km(of: point, in: near), 1)
        XCTAssertEqual(RiddleHint.openRunsWithin50km(of: point, in: far), 0)
    }

    // MARK: - Смещение центра

    func testCentreIsOffsetByNoMoreThanHalfTheRadiusAndIsNeverTheRiddleItself() {
        let point = CLLocationCoordinate2D(latitude: 45.04, longitude: 38.97)
        for id in ["pass:u0h2w1q", "lighthouse:ubh0k3m", "ferry:sv8dz7t", "dam:u1e2f3g"] {
            for radius in [5_000.0, 17_500.0, 30_000.0] {
                let centre = RiddleHint.offsetCentre(for: id, around: point, radius: radius)
                let shift = CLLocation(latitude: point.latitude, longitude: point.longitude)
                    .distance(from: CLLocation(latitude: centre.latitude, longitude: centre.longitude))
                XCTAssertLessThanOrEqual(shift, radius / 2 + 1, "\(id) на радиусе \(radius)")
                XCTAssertGreaterThan(shift, radius * 0.2, "\(id): загадка не стоит в середине круга")
            }
        }
    }

    func testOffsetIsDeterministic() {
        let point = CLLocationCoordinate2D(latitude: 45.04, longitude: 38.97)
        let first = RiddleHint.offsetCentre(for: "pass:u0h2w1q", around: point, radius: 20_000)
        let second = RiddleHint.offsetCentre(for: "pass:u0h2w1q", around: point, radius: 20_000)
        XCTAssertEqual(first.latitude, second.latitude)
        XCTAssertEqual(first.longitude, second.longitude)

        let other = RiddleHint.offsetCentre(for: "pass:u0h2w1r", around: point, radius: 20_000)
        XCTAssertNotEqual(first.latitude, other.latitude)
    }

    /// Хеш заморожен: сменится он — переедут все круги разом, и человек
    /// прочтёт это как «загадки переехали».
    func testHashIsTheFrozenFNVAndNotSwiftsSaltedOne() {
        XCTAssertEqual(RiddleHint.hash("bridge:demo-psekups"), 13_126_220_764_454_929_469)
        XCTAssertEqual(RiddleHint.hash("lighthouse:u0h2w1q"), 782_801_610_538_195_241)
    }

    // MARK: - Что видно от значка на этом масштабе

    /// Порог ОДИН, и уровня осталось два.
    ///
    /// Владелец на устройстве 16 сен: на стране три «?» со строками съезжаются
    /// в кучу поверх подписи «КРАСНОДАРСКИЙ КРАЙ». Круг задан в метрах, значок
    /// — в точках экрана, и на дальнем зуме три круга по тридцать километров
    /// помещаются в один палец. Строку с карты 17 сен сняли совсем («сильно
    /// много внимания на себя берут секреты и кружки вокруг них»), и вместе с
    /// ней ушёл верхний уровень: показывать по-крупному стало нечего.
    func testBadgeAppearsOnlyWhenItsCircleIsBigEnoughToHoldIt() {
        // Страна: круг 30 км на экране в полпальца — не показываем ничего,
        // счёт несёт строка листа «N загадок рядом».
        XCTAssertEqual(HintBadgeLOD.level(diameterPt: 20), .none)
        XCTAssertEqual(HintBadgeLOD.level(diameterPt: 59.9), .none)
        // Круг уже читается как круг — значку есть к чему привязаться.
        XCTAssertEqual(HintBadgeLOD.level(diameterPt: 60), .badge)
        XCTAssertEqual(HintBadgeLOD.level(diameterPt: 159), .badge)
        // Выше порога уровень БОЛЬШЕ НЕ РАСТЁТ: строки на карте нет, и
        // «полный» уровень вернул бы её вместе с кучей на стране.
        XCTAssertEqual(HintBadgeLOD.level(diameterPt: 160), .badge)
        XCTAssertEqual(HintBadgeLOD.level(diameterPt: 900), .badge)
    }

    /// Значок — диск размером с ноготь, и строки под ним нет ни одной.
    ///
    /// Проверяется деревом вью, а не глазами: подпись, вернувшаяся на карту
    /// новой строкой кода, иначе заметна только на устройстве. `UILabel` в
    /// подвидах ровно один — сам «?».
    func testBadgeCarriesNoCaptionOnTheMap() {
        let view = RiddleHintView(
            annotation: RiddleHintAnnotation(
                hint: RiddleHint(id: "a", type: .lighthouse,
                                 centre: CLLocationCoordinate2D(latitude: 45, longitude: 39),
                                 radiusMetres: 10_000),
                line: "Где-то здесь дорога упирается в море"),
            reuseIdentifier: RiddleHintView.reuseID)

        let labels = view.subviews.compactMap { $0 as? UILabel }
        XCTAssertEqual(labels.count, 1, "на карте у подсказки только «?» — строка живёт в карточке")
        XCTAssertEqual(labels.first?.text, "?")
        XCTAssertEqual(view.bounds.width, RiddleHintView.badgeSide)
        XCTAssertEqual(labels.first?.alpha, RiddleHintView.badgeAlpha)
        // Незрячему «?» без подписи не говорит ничего — VoiceOver строку
        // получает, экран нет.
        XCTAssertEqual(view.accessibilityLabel, "Где-то здесь дорога упирается в море")
    }

    /// Значок уступает печати находки и ПОБЕЖДАЕТ подпись региона.
    ///
    /// MapKit при столкновении прячет проигравшего — то есть выбор приоритета
    /// здесь это выбор «кто из двоих исчезнет». Уступить обязана подпись: она
    /// повторяется на каждом шагу, а нерешённых загадок на карте три.
    func testHintBadgeYieldsToSealsAndBeatsRegionLabels() {
        let hint = RiddleHintView(
            annotation: RiddleHintAnnotation(
                hint: RiddleHint(id: "a", type: .lighthouse,
                                 centre: CLLocationCoordinate2D(latitude: 45, longitude: 39),
                                 radiusMetres: 10_000),
                line: "линия"),
            reuseIdentifier: RiddleHintView.reuseID)

        XCTAssertEqual(hint.displayPriority, .defaultHigh)
        XCTAssertEqual(hint.collisionMode, .circle)
        XCTAssertLessThan(hint.displayPriority.rawValue, MKFeatureDisplayPriority.required.rawValue,
                          "найденная печать сильнее ненайденной загадки")
        XCTAssertGreaterThan(hint.displayPriority.rawValue,
                             MKFeatureDisplayPriority.defaultLow.rawValue,
                             "подпись региона (.defaultLow) обязана уступать, а не наоборот")

        // Уровень прячет значок целиком, а не делает его прозрачным: скрытая
        // аннотация не участвует ни в столкновениях, ни в хит-тесте.
        hint.lod = .none
        XCTAssertTrue(hint.isHidden)
        hint.lod = .badge
        XCTAssertFalse(hint.isHidden)
    }

    /// Порядок в плане — ответ на «кто из двух совпавших кругов важнее»:
    /// ближайший к открытому идёт первым, и именно в этом порядке подсказки
    /// уезжают на карту.
    func testPlanIsOrderedNearestToTheOpenWorldFirst() {
        let home = [CLLocationCoordinate2D(latitude: 45.0, longitude: 39.0)]
        let hints = RiddleHint.plan(
            riddles: [
                riddle("far", lat: 45.5, lon: 39.0),
                riddle("near", lat: 45.05, lon: 39.0),
                riddle("mid", lat: 45.2, lon: 39.0),
            ],
            solvedRiddleIds: [], centroids: home, layer: emptyLayer)
        XCTAssertEqual(hints.map(\.id), ["near", "mid", "far"])
    }

    // MARK: - Три ближайшие

    func testOnlyThreeNearestUnsolvedRiddlesAreShown() {
        let home = [CLLocationCoordinate2D(latitude: 45.0, longitude: 39.0)]
        let riddles = [
            riddle("a", lat: 45.1, lon: 39.0),   // ~11 км
            riddle("b", lat: 45.3, lon: 39.0),   // ~33 км
            riddle("c", lat: 45.5, lon: 39.0),   // ~56 км
            riddle("d", lat: 46.5, lon: 39.0),   // ~167 км
            riddle("e", lat: 50.0, lon: 39.0),   // ~556 км
        ]

        let hints = RiddleHint.plan(
            riddles: riddles, solvedRiddleIds: [], centroids: home, layer: emptyLayer)

        XCTAssertEqual(hints.map(\.id), ["a", "b", "c"])
    }

    func testSolvedRiddleFreesItsSlotForTheNextOne() {
        let home = [CLLocationCoordinate2D(latitude: 45.0, longitude: 39.0)]
        let riddles = [
            riddle("a", lat: 45.1, lon: 39.0),
            riddle("b", lat: 45.3, lon: 39.0),
            riddle("c", lat: 45.5, lon: 39.0),
            riddle("d", lat: 46.5, lon: 39.0),
        ]

        let hints = RiddleHint.plan(
            riddles: riddles, solvedRiddleIds: ["b"], centroids: home, layer: emptyLayer)

        XCTAssertEqual(hints.map(\.id), ["a", "c", "d"])
    }

    /// Открытого нет — подсказок нет: круг на карте, где человек нигде не был,
    /// указывает не на загадку, а на случайную точку мира.
    func testNoOpenTerritoryMeansNoHints() {
        XCTAssertTrue(RiddleHint.plan(
            riddles: [riddle("a", lat: 45.1, lon: 39.0)],
            solvedRiddleIds: [], centroids: [], layer: emptyLayer).isEmpty)
    }

    /// Близость считается до БЛИЖАЙШЕГО центроида, а не до первого: открытых
    /// кусков у человека несколько, и дача на севере не делает загадку у моря
    /// далёкой.
    func testDistanceIsMeasuredToTheNearestOpenRegion() {
        let centroids = [
            CLLocationCoordinate2D(latitude: 55.0, longitude: 37.0),
            CLLocationCoordinate2D(latitude: 45.0, longitude: 39.0),
        ]
        let hints = RiddleHint.plan(
            riddles: [riddle("south", lat: 45.1, lon: 39.0), riddle("north", lat: 54.0, lon: 37.0)],
            solvedRiddleIds: [], centroids: centroids, layer: emptyLayer, limit: 1)

        XCTAssertEqual(hints.map(\.id), ["south"])
    }
}
