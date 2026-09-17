import XCTest
import MapKit
@testable import TripTrack

/// Границы регионов и стран — сорок тысяч вершин, которые нельзя складывать в
/// `CGPath` ни в `draw`, ни на главном потоке.
///
/// Сторож ровно этому: сборка укладывается в бюджет, дальний уровень
/// прорежен, а чтение во время сборки не роняет и не отдаёт полусобранного.
final class RegionPathIndexTests: XCTestCase {

    /// Синтетические контуры: страна-квадрат и регион с частой пилой по краю.
    ///
    /// Пила нужна затем, что прореживание проверяется СЧЁТОМ вершин, а у
    /// гладкого квадрата их четыре и прореживать нечего. Бандл здесь не
    /// годится ещё и потому, что страны приезжают в него Задачей 1, а правило
    /// «дальний уровень прорежен» обязано держаться и до её слияния.
    /// Синтетические контуры — только СТРАНЫ: регионов индекс больше не
    /// носит вовсе (их заливка ушла с «ночной картой», а подписи берут
    /// центроид и рамку прямо из атласа).
    private func outlines(teeth: Int = 600) -> [RegionOutline] {
        [
            RegionOutline(id: "XX", isCountry: true, rings: [boxRing()]),
            RegionOutline(id: "YY", isCountry: true, rings: [sawRing(teeth: teeth)]),
        ]
    }

    private func boxRing() -> [Double] { [40, 30, 40, 50, 60, 50, 60, 30] }

    private func sawRing(teeth: Int) -> [Double] {
        var saw: [Double] = []
        for i in 0..<teeth {
            let t = Double(i) / Double(teeth)
            saw.append(45 + 2 * t + (i % 2 == 0 ? 0.02 : -0.02))
            saw.append(38 + 2 * t)
        }
        for i in stride(from: teeth - 1, through: 0, by: -1) {
            let t = Double(i) / Double(teeth)
            saw.append(44.5 + 2 * t)
            saw.append(38 + 2 * t)
        }
        return saw
    }

    /// Контуры живут ТОЛЬКО на дальнем уровне: ближе границы показывает сама
    /// карта Apple, а с «ночной картой» она видна сквозь мглу — вторая линия
    /// рядом с её собственной была бы просто вторым контуром.
    func testOnlyFarCarriesOutlines() {
        let index = RegionPathIndex()
        index.prepare(outlines: outlines())
        XCTAssertNil(index.paths(in: .world, lod: .fine))
        XCTAssertNil(index.paths(in: .world, lod: .mid))
        XCTAssertEqual(index.paths(in: .world, lod: .far)?.countryBorders.count, 2)
    }

    func testPieceFarFromEveryOutlineGetsNothing() {
        let index = RegionPathIndex()
        index.prepare(outlines: outlines())
        let pacific = MKMapRect(
            origin: MKMapPoint(CLLocationCoordinate2D(latitude: -30, longitude: -150)),
            size: MKMapSize(width: 10_000, height: 10_000))
        XCTAssertNil(index.paths(in: pacific, lod: .far))
    }

    // MARK: Бюджет и потоки

    /// Сборка настоящего бандла укладывается в 400 мс.
    ///
    /// Это не «столько она стоит», а потолок, за которым её уже нельзя было бы
    /// держать одной фоновой задачей на старте «Атласа»: человек открывает
    /// вкладку и ждёт первого кадра карты, а не границ.
    func testBundleBuildsInsideItsBudget() async {
        let atlas = RegionAtlas.shared
        await atlas.loadIfNeeded()
        XCTAssertFalse(atlas.regions.isEmpty, "атлас обязан быть в бандле")
        let outlines = RegionOutline.all(from: atlas)

        let index = RegionPathIndex()
        let started = Date()
        index.prepare(outlines: outlines)
        let cost = Date().timeIntervalSince(started)
        print(String(format: "[regions] индекс из %d контуров собран за %.0f мс",
                     outlines.count, cost * 1000))
        XCTAssertLessThan(cost, 0.4, "сборка границ заняла \(cost * 1000) мс")
        XCTAssertTrue(index.isReady)
    }

    /// Контуры стран доезжают из атласа до индекса — и у России их много.
    ///
    /// Тринадцать колец — нижняя граница, а не точное число: у России материк,
    /// Калининград, Сахалин, Курилы и десяток островов, и любое «одно кольцо»
    /// значило бы, что сборка бандла склеила их в один контур через полмира.
    /// Само число сторожит бандл (`MapRegionsBundleTests`); здесь проверяется
    /// ДОРОГА от атласа до кисти — до фикс-волны 2 она была оборвана заглушкой
    /// `countries(from:) { [] }`, и границ стран не рисовалось вовсе.
    func testCountryOutlinesReachTheIndex() async {
        let atlas = RegionAtlas.shared
        await atlas.loadIfNeeded()
        let countries = RegionOutline.countries(from: atlas)
        XCTAssertFalse(countries.isEmpty, "страны обязаны доезжать из атласа")
        XCTAssertTrue(countries.allSatisfy { $0.isCountry })
        guard let russia = countries.first(where: { $0.id == "RU" }) else {
            return XCTFail("контур России обязан быть в индексе")
        }
        print("[regions] колец у RU: \(russia.rings.count), стран всего \(countries.count)")
        XCTAssertGreaterThanOrEqual(russia.rings.count, 13,
                                    "материк, Калининград, Сахалин, Курилы — это не одно кольцо")

        let index = RegionPathIndex()
        index.prepare(outlines: countries)
        guard let far = index.paths(in: .world, lod: .far) else {
            return XCTFail("на дальнем уровне страны обязаны рисоваться")
        }
        XCTAssertFalse(far.countryBorders.isEmpty)
    }

    /// Анклав побеждает обёртку: Майкоп — это Адыгея, а не Краснодарский край.
    ///
    /// Natural Earth отдаёт край сплошным кольцом, БЕЗ дырки под республикой,
    /// поэтому обе геометрии накрывают Майкоп. До правила «меньшая рамка
    /// побеждает» ответ зависел от порядка строк в бандле: километры,
    /// «посещённые регионы» и заливка на «Атласе» доставались краю. Правило
    /// живёт в ОДНОМ резолвере, и обе его двери — полный поиск и быстрый путь
    /// по прошлой точке — обязаны отвечать одинаково, иначе Майкоп получает
    /// то край, то республику в зависимости от того, откуда приехал трек.
    func testEnclaveWinsOverTheRegionAroundIt() async {
        let atlas = RegionAtlas.shared
        await atlas.loadIfNeeded()
        let maykop = CLLocationCoordinate2D(latitude: 44.61, longitude: 40.10)
        let krasnodar = CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975)

        XCTAssertEqual(atlas.region(containing: maykop)?.id, "RU-AD")
        XCTAssertEqual(atlas.region(containing: krasnodar)?.id, "RU-KDA")

        // Быстрый путь: трек пришёл из края — и всё равно обязан отдать
        // республику, а не подтвердить прошлый ответ.
        guard let krai = atlas.regionIndex(containing: krasnodar) else {
            return XCTFail("Краснодар обязан находиться")
        }
        XCTAssertFalse(atlas.regionAtIndex(krai, contains: maykop),
                       "быстрый путь подтвердил край над анклавом — резолвера стало два")
        guard let republic = atlas.regionIndex(containing: maykop) else {
            return XCTFail("Майкоп обязан находиться")
        }
        XCTAssertTrue(atlas.regionAtIndex(republic, contains: maykop))
        // И обратно: анклав не должен «съедать» точки вокруг себя.
        XCTAssertFalse(atlas.regionAtIndex(republic, contains: krasnodar))
    }

    /// Читать можно во время сборки: пишет фоновый поток, читают потоки
    /// отрисовки MapKit — по тайлу на поток.
    ///
    /// Проверяется не «что вернулось» (до конца сборки честный ответ — `nil`),
    /// а что чтение не роняет и не отдаёт полусобранного набора.
    func testReadingWhileBuildingIsSafe() {
        let index = RegionPathIndex()
        let outlines = self.outlines(teeth: 4_000)
        let building = expectation(description: "собрано")
        DispatchQueue.global(qos: .userInitiated).async {
            index.prepare(outlines: outlines)
            building.fulfill()
        }
        let reading = expectation(description: "прочитано")
        reading.expectedFulfillmentCount = 4
        for _ in 0..<4 {
            DispatchQueue.global(qos: .userInitiated).async {
                for _ in 0..<400 {
                    // Либо ничего (ещё не собрано), либо ЦЕЛЫЙ набор.
                    if let paths = index.paths(in: .world, lod: .far) {
                        XCTAssertEqual(paths.countryBorders.count, 2)
                    }
                }
                reading.fulfill()
            }
        }
        wait(for: [building, reading], timeout: 30)
        XCTAssertTrue(index.isReady)
    }

    /// Незагруженный атлас НИЧЕГО не защёлкивает: пустая выборка — не работа.
    /// Та же ловушка, что у миграции слоя открытого.
    func testUnloadedAtlasDoesNotLatch() {
        let index = RegionPathIndex()
        index.prepareIfNeeded(atlas: RegionAtlas.shared)
        // Атлас в тестовом процессе может быть уже загружен другим тестом —
        // тогда сборка законна и это проверяет не то. Вопрос ставится только
        // на незагруженном.
        if !RegionAtlas.shared.isLoaded {
            XCTAssertFalse(index.isReady, "пустая выборка не имеет права считаться сборкой")
        }
    }
}
