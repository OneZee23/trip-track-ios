import XCTest
import CoreLocation
@testable import TripTrack

/// Бандл загадок и его каталог.
///
/// Файл собирает `Tools/build_secrets.py` из OSM (ODbL) и Wikidata (CC0), и
/// проверять его надо здесь, а не глазами: точка, уехавшая в море или
/// потерявшая тип, выглядит в JSON ровно так же, как правильная.
final class RiddleCatalogTests: XCTestCase {

    private static let bundled = BundleRiddleCatalog()

    // MARK: - Бандл

    func testBundleLoadsAndIsNotEmpty() throws {
        let riddles = Self.bundled.all()
        XCTAssertFalse(riddles.isEmpty,
                       "Riddles.json не попал в бандл или пуст — загадок не будет вовсе")
    }

    func testEveryIdIsUniqueAndSpelledTypeColonCell() {
        var seen = Set<String>()
        for riddle in Self.bundled.all() {
            XCTAssertTrue(seen.insert(riddle.id).inserted, "дубль id: \(riddle.id)")
            let parts = riddle.id.split(separator: ":")
            XCTAssertEqual(parts.count, 2, "id не «тип:ячейка»: \(riddle.id)")
            XCTAssertEqual(String(parts[0]), riddle.type.rawValue,
                           "тип в id разошёлся с полем: \(riddle.id)")
            XCTAssertEqual(parts[1].count, 7, "ячейка не geohash-7: \(riddle.id)")
            XCTAssertEqual(
                String(parts[1]),
                GeohashEncoder.encode(latitude: riddle.coordinate.latitude,
                                      longitude: riddle.coordinate.longitude, precision: 7),
                "ячейка в id не совпадает с координатой: \(riddle.id)")
        }
    }

    func testCoordinatesAreRealNumbers() {
        for riddle in Self.bundled.all() {
            XCTAssertTrue(CLLocationCoordinate2DIsValid(riddle.coordinate), riddle.id)
            XCTAssertNotEqual(riddle.coordinate.latitude, 0, riddle.id)
            XCTAssertNotEqual(riddle.coordinate.longitude, 0, riddle.id)
        }
    }

    /// `r` — это либо настоящий регион атласа, либо `nil`. Третьего не бывает:
    /// выдуманный id региона тихо превратился бы в пустую подпись на карточке.
    func testRegionIdEitherExistsInTheAtlasOrIsAbsent() async {
        await RegionAtlas.shared.loadIfNeeded()
        let atlas = RegionAtlas.shared
        guard !atlas.regions.isEmpty else {
            XCTFail("атлас не загрузился — проверять нечего")
            return
        }
        for riddle in Self.bundled.all() {
            guard let regionId = riddle.regionId else { continue }
            XCTAssertNotNil(atlas.region(id: regionId),
                            "\(riddle.id) ссылается на регион \(regionId), которого в атласе нет")
        }
    }

    /// Все двенадцать типов имеют свой символ печати и свой радиус зачёта.
    func testEveryTypeHasReachAndSymbol() {
        XCTAssertEqual(RiddleType.allCases.count, 12)
        var symbols = Set<SealSymbol>()
        for type in RiddleType.allCases {
            XCTAssertTrue(type.reach >= 300 && type.reach <= 1000, type.rawValue)
            symbols.insert(type.symbol)
        }
        XCTAssertEqual(symbols.count, 12, "два типа делят один символ печати")
    }

    // MARK: - Предфильтр по ячейкам

    /// Каталог из трёх точек: в ячейке трека, в соседней с ней и далеко.
    private func makeCatalog() throws -> (RiddleCatalog, here: Riddle, near: Riddle, far: Riddle) {
        let here = Riddle(id: "pass:\(cell(43.6, 41.4, 7))", type: .pass,
                          coordinate: .init(latitude: 43.6, longitude: 41.4),
                          name: "Here", regionId: nil)
        // Соседняя geohash-5 ячейка: сдвиг заведомо больше одной ячейки (~5 км).
        let nearCoordinate = CLLocationCoordinate2D(latitude: 43.66, longitude: 41.46)
        let near = Riddle(id: "dam:\(cell(43.66, 41.46, 7))", type: .dam,
                          coordinate: nearCoordinate, name: "Near", regionId: nil)
        let far = Riddle(id: "ferry:\(cell(59.9, 30.3, 7))", type: .ferry,
                         coordinate: .init(latitude: 59.9, longitude: 30.3),
                         name: "Far", regionId: nil)
        let payload: [String: Any] = [
            "v": 1,
            "riddles": [here, near, far].map { riddle in
                [
                    "id": riddle.id, "t": riddle.type.rawValue,
                    "c": [riddle.coordinate.latitude, riddle.coordinate.longitude],
                    "n": riddle.name,
                ] as [String: Any]
            },
        ]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("riddles-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: payload).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return (BundleRiddleCatalog(url: url), here, near, far)
    }

    private func cell(_ lat: Double, _ lon: Double, _ precision: Int) -> String {
        GeohashEncoder.encode(latitude: lat, longitude: lon, precision: precision)
    }

    func testCandidatesTakeTheCellAndItsEightNeighbours() throws {
        let (catalog, here, near, far) = try makeCatalog()
        let trackCell = cell(43.6, 41.4, 5)
        let found = catalog.candidates(near: [trackCell])
        let ids = Set(found.map(\.id))
        XCTAssertTrue(ids.contains(here.id), "своя ячейка потерялась")
        XCTAssertTrue(ids.contains(near.id),
                      "соседняя ячейка не взята — точка у края ячейки ближе к соседней")
        XCTAssertFalse(ids.contains(far.id), "Петербург попал в кандидаты Кавказа")
    }

    func testEmptyTrackGivesNoCandidates() throws {
        let (catalog, _, _, _) = try makeCatalog()
        XCTAssertTrue(catalog.candidates(near: []).isEmpty)
        XCTAssertEqual(catalog.all().count, 3)
    }

    /// Файла нет — пустой каталог и никакого падения: карта без загадок хуже
    /// карты с ними, но упавшее приложение хуже обеих.
    func testMissingFileGivesAnEmptyCatalog() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-such-riddles-\(UUID().uuidString).json")
        let catalog = BundleRiddleCatalog(url: url)
        XCTAssertTrue(catalog.all().isEmpty)
        XCTAssertTrue(catalog.candidates(near: ["ubcr4"]).isEmpty)
    }

    func testRiddleSurvivesACodableRoundTrip() throws {
        let riddle = Riddle(id: "pass:ubcr4xk", type: .pass,
                            coordinate: .init(latitude: 43.6234, longitude: 41.4571),
                            name: "Gumbashi Pass", regionId: "RU-KC")
        let data = try JSONEncoder().encode(riddle)
        let back = try JSONDecoder().decode(Riddle.self, from: data)
        XCTAssertEqual(riddle, back)
        XCTAssertEqual(back.regionId, "RU-KC")
    }
}
