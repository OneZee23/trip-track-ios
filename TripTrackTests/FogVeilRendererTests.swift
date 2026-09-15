import XCTest
import MapKit
@testable import TripTrack

/// Туман 0.7.0 рисуется не «тёмной картой», а непрозрачной вуалью с мягкими
/// коридорами. Три вещи в этом рендерере обязаны быть чистыми функциями, иначе
/// проверить их нечем: перо (сколько проходов и какой альфой), выбор уровня
/// детали по зуму и пространственный индекс путей.
///
/// Четвёртая — сама заливка: у неё нет «правильного значения», но есть
/// свойство, которое видно глазом и ловится числом — край коридора обязан
/// гаснуть монотонно, без террас (ровно тем, чем была плоха подобранная руками
/// таблица пера в 0.6.x).
final class FogVeilRendererTests: XCTestCase {

    // MARK: - Перо

    /// Ширины идут от полной к узкой и НИКОГДА не растут: каждый следующий
    /// проход стирает уже внутри того, что стёр предыдущий.
    func testFeatherWidthsShrinkMonotonically() {
        for passes in [8, 14] {
            let table = FogVeilRenderer.feather(passes: passes)
            XCTAssertEqual(table.count, passes)
            XCTAssertEqual(table[0].width, 1, accuracy: 0.0001, "первый проход — вся ширина коридора")
            for i in 1..<table.count {
                XCTAssertLessThan(table[i].width, table[i - 1].width,
                                  "проход \(i) шире предыдущего — перо вывернулось наизнанку")
            }
            XCTAssertEqual(
                table[table.count - 1].width, 0.18, accuracy: 0.001,
                "последний проход обязан прочистить середину коридора, а не оставить нитку")
        }
    }

    /// Альфы не подобраны руками, а выведены из кривой `pow(1-t, 1.7)`:
    /// произведение «сколько вуали осталось» после k проходов обязано лежать
    /// точно на ней. Подобранные руками четыре ступени рисовали вокруг каждой
    /// дороги террасы, как на топографической карте, — отсюда и правило.
    func testFeatherAlphasFollowTheCurve() {
        let passes = 14
        let table = FogVeilRenderer.feather(passes: passes)
        var remaining: CGFloat = 1
        for (index, pass) in table.enumerated() {
            XCTAssertGreaterThanOrEqual(pass.alpha, 0)
            XCTAssertLessThanOrEqual(pass.alpha, 1)
            remaining *= (1 - pass.alpha)
            let t = CGFloat(index + 1) / CGFloat(passes)
            XCTAssertEqual(remaining, pow(1 - t, 1.7), accuracy: 0.002,
                           "после \(index + 1) проходов вуали осталось не по кривой")
        }
        XCTAssertEqual(remaining, 0, accuracy: 0.002, "середина коридора обязана очиститься полностью")
    }

    /// Число проходов — от ЭКРАННОЙ ширины коридора, а не константой: на
    /// широком коридоре восьми ступеней хватает ровно до тех пор, пока вуаль
    /// полупрозрачна (её прозрачность и съедала ступени). На альфе 1.0 их
    /// становится видно, и только там платим четырнадцатью.
    func testPassCountFollowsScreenWidth() {
        XCTAssertEqual(FogVeilRenderer.passes(forScreenWidth: 20, lod: .fine), 8)
        XCTAssertEqual(FogVeilRenderer.passes(forScreenWidth: 60, lod: .fine), 8)
        XCTAssertEqual(FogVeilRenderer.passes(forScreenWidth: 61, lod: .fine), 14)
        XCTAssertEqual(FogVeilRenderer.passes(forScreenWidth: 400, lod: .fine), 14)
    }

    /// На среднем и дальнем уровне перьев вчетверо меньше, и ширина на это не
    /// влияет: коридор там шириной в двенадцать экранных точек, разницы между
    /// четырьмя ступенями и четырнадцатью на ней не видит никто, а платятся
    /// они на КАЖДОМ тайле — в тот самый момент, когда после зума наружу их
    /// разом просят десяток.
    func testFarAndMidAlwaysGetFourPasses() {
        for lod in [RevealedLayer.LOD.mid, .far] {
            XCTAssertEqual(FogVeilRenderer.passes(forScreenWidth: 20, lod: lod), 4)
            XCTAssertEqual(FogVeilRenderer.passes(forScreenWidth: 400, lod: lod), 4)
        }
    }

    // MARK: - Уровни детали

    func testLodThresholds() {
        XCTAssertEqual(FogVeilRenderer.lod(for: 0.06), .fine, "улица")
        XCTAssertEqual(FogVeilRenderer.lod(for: 2e-3), .fine, "город")
        XCTAssertEqual(FogVeilRenderer.lod(for: 1.5e-3), .mid, "граница: ровно порог — уже средний")
        XCTAssertEqual(FogVeilRenderer.lod(for: 5e-4), .mid, "регион")
        XCTAssertEqual(FogVeilRenderer.lod(for: 1.5e-4), .far, "граница: ровно порог — уже дальний")
        XCTAssertEqual(FogVeilRenderer.lod(for: 3e-5), .far, "страна")
    }

    /// Ширина коридора: метры побеждают на улице, экранный пол — на стране.
    /// Обе половины формулы обязаны работать, иначе туман либо съедает город,
    /// либо теряет дорогу на масштабе страны.
    func testCorridorWidthTakesMetresUpCloseAndScreenPointsFarAway() {
        let latitude = 45.035
        let metre = MKMapPointsPerMeterAtLatitude(latitude)

        let street = FogVeilRenderer.corridorWidth(zoomScale: 0.06, metre: metre)
        XCTAssertEqual(street, CGFloat(FogVeilRenderer.streetHalfWidthMetres * 2 * metre), accuracy: 0.001,
                       "на улице коридор обязан быть ±50 м, а не экранным полом")

        let country = FogVeilRenderer.corridorWidth(zoomScale: 3e-5, metre: metre)
        XCTAssertEqual(country, FogVeilRenderer.minVeinPoints / 3e-5, accuracy: 0.001,
                       "на стране побеждает пол в экранных точках")
        XCTAssertEqual(country * 3e-5, FogVeilRenderer.minVeinPoints, accuracy: 0.001,
                       "на экране это ровно 12 точек, ниже которых коридор читается линией по чёрному")
    }

    // MARK: - Индекс путей

    /// Двухуровневый индекс: на улице тайл обязан получать только свои
    /// несколько километров сети, а не весь город одним `CGPath`.
    func testChunksAreBucketedTwiceSoStreetZoomSkipsTheRestOfTheCity() {
        // Восемь коротких отрезков по 100 м, по прямой с шагом 12 км —
        // разные мелкие бакеты (4.8 км), один-два крупных (78 км).
        var lines: [MKPolyline] = []
        for i in 0..<8 {
            let lat = 45.0 + Double(i) * 12_000 / 111_320
            var coords = [
                CLLocationCoordinate2D(latitude: lat, longitude: 38.9),
                CLLocationCoordinate2D(latitude: lat + 100 / 111_320, longitude: 38.9),
            ]
            lines.append(MKPolyline(coordinates: &coords, count: 2))
        }
        let chunks = MapPathChunks(lines) { CGPoint(x: $0.x, y: $0.y) }

        // Спрашиваем про середину цепочки: крайние отрезки попадают в свой
        // крупный бакет поодиночке, и тогда сравнивать было бы нечего.
        let middle = lines[3].boundingMapRect
        let fine = chunks.visiblePaths(in: middle, zoomScale: 0.01)
        let coarse = chunks.visiblePaths(in: middle, zoomScale: 1e-5)

        // Считать надо не число путей, а ГЕОМЕТРИЮ в них: бакет отдаёт один
        // склеенный `CGPath`, и крупный бакет — это один путь на всю сеть.
        let fineSpan = fine.reduce(0) { max($0, $1.boundingBox.height) }
        let coarseSpan = coarse.reduce(0) { max($0, $1.boundingBox.height) }

        XCTAssertFalse(fine.isEmpty, "своя дорога обязана прийти на любом зуме")
        XCTAssertGreaterThan(
            coarseSpan, fineSpan * 20,
            "на дальнем зуме бакет крупный и тащит сеть целиком — это и дешевле")
        // 100 м пути на широте 45° — около тысячи точек карты; вся цепочка в
        // 84 км — около восьмисот тысяч.
        XCTAssertLessThan(
            fineSpan, 2_000,
            "на улице в тайл приехала чужая геометрия: пролёт \(fineSpan) точек карты")
    }

    func testChunksReturnNothingFarFromTheNetwork() {
        var coords = [
            CLLocationCoordinate2D(latitude: 45.0, longitude: 38.9),
            CLLocationCoordinate2D(latitude: 45.01, longitude: 38.91),
        ]
        let chunks = MapPathChunks([MKPolyline(coordinates: &coords, count: 2)]) {
            CGPoint(x: $0.x, y: $0.y)
        }
        // Степь в 900 км.
        let origin = MKMapPoint(CLLocationCoordinate2D(latitude: 53.0, longitude: 45.0))
        let empty = MKMapRect(x: origin.x, y: origin.y, width: 1_000, height: 1_000)

        XCTAssertTrue(chunks.visiblePaths(in: empty, zoomScale: 0.01).isEmpty)
        XCTAssertTrue(chunks.visiblePaths(in: empty, zoomScale: 1e-5).isEmpty)
    }

    func testEmptyChunksAreEmptyAtEveryZoom() {
        let chunks = MapPathChunks([]) { CGPoint(x: $0.x, y: $0.y) }
        XCTAssertTrue(chunks.visiblePaths(in: .world, zoomScale: 0.01).isEmpty)
        XCTAssertTrue(chunks.visiblePaths(in: .world, zoomScale: 1e-5).isEmpty)
    }

    /// Путь, пересекающий границу мелкого бакета, обязан находиться С ОБЕИХ
    /// сторон. Поведение верное и без этого теста — ключ бакета берётся по
    /// середине bbox, а `rect` чанка это ОБЪЕДИНЕНИЕ bbox всех его линий, — но
    /// держится оно ровно на объединении, а не на очевидности: стоит кому-то
    /// заменить `union` на «прямоугольник бакета», и половина улицы пропадёт с
    /// одной стороны границы, причём только на близком зуме.
    func testPathCrossingAFineBucketBorderIsFoundFromTheOtherSide() {
        let bucket = MKMapSize.world.width / 8_192
        let anchor = MKMapPoint(CLLocationCoordinate2D(latitude: 45.0, longitude: 38.9))
        let border = (anchor.x / bucket).rounded(.down) * bucket + bucket

        let west = MKMapPoint(x: border - bucket * 0.45, y: anchor.y).coordinate
        let east = MKMapPoint(x: border + bucket * 0.45, y: anchor.y).coordinate
        var coords = [west, east]
        let chunks = MapPathChunks([MKPolyline(coordinates: &coords, count: 2)]) {
            CGPoint(x: $0.x, y: $0.y)
        }

        // Тайл целиком по западную сторону границы — то есть в бакете, который
        // ключом НЕ выбирался (середина bbox пришлась ровно на границу).
        let probe = MKMapRect(
            x: border - bucket * 0.4, y: anchor.y - 10, width: bucket * 0.1, height: 20)
        XCTAssertFalse(
            chunks.visiblePaths(in: probe, zoomScale: 0.01).isEmpty,
            "дорога, перешагнувшая границу бакета, пропала с одной из сторон")
    }

    // MARK: - Сама заливка

    /// Снимок пера на фиксированной геометрии: одна прямая дорога посреди
    /// тайла. По перпендикуляру к ней вуаль обязана нарастать МОНОТОННО от
    /// прочищенной середины к сплошной темноте — ни одной ступени назад.
    ///
    /// Это тот самый тест, который отличает мягкий край от контурной карты, и
    /// он ходит через `FogVeilPainter`, а не через рендерер: постер
    /// «Поделиться» рисует тем же кодом (`MKMapSnapshotter` оверлеев не
    /// рендерит), и разъехаться этим двум картинкам нельзя.
    func testPainterEdgeFadesWithoutTerraces() {
        let size = 240
        let pixels = Self.drawn(size: size) { context, rect in
            // Горизонтальная дорога по центру.
            let road = CGMutablePath()
            road.move(to: CGPoint(x: -20, y: rect.midY))
            road.addLine(to: CGPoint(x: rect.maxX + 20, y: rect.midY))
            FogVeilPainter.paint(
                context: context, paths: [road], corridorWidth: 90, passes: 14,
                tileRect: rect, depth: .flat
            )
        }

        let column = size / 2
        let alphas = ((size / 2)..<size).map { Int(pixels[($0 * size + column) * 4 + 3]) }

        XCTAssertLessThan(alphas[0], 12, "середина коридора обязана быть прочищена насквозь")
        XCTAssertGreaterThan(alphas[alphas.count - 1], 245, "за коридором вуаль непрозрачна")
        for i in 1..<alphas.count {
            XCTAssertGreaterThanOrEqual(
                alphas[i], alphas[i - 1] - 1,
                "альфа упала на \(i)-м пикселе от оси: \(alphas[i - 1]) → \(alphas[i]) — это терраса"
            )
        }
    }

    /// Тайл, до которого не доехали, — сплошная темнота: ни одного пикселя
    /// светлее объёмной дымки и ни одного прозрачного.
    func testPainterFillsAnEmptyTileOpaque() {
        let size = 64
        let pixels = Self.drawn(size: size) { context, rect in
            FogVeilPainter.paint(
                context: context, paths: [], corridorWidth: 90, passes: 8,
                tileRect: rect, depth: .flat
            )
        }

        for i in stride(from: 0, to: size * size * 4, by: 4) {
            XCTAssertEqual(Int(pixels[i + 3]), 255, "вуаль обязана быть непрозрачной")
            // Объёмная дымка не светлее ~(0.10, 0.11, 0.15): ярче — и полоса
            // недогруженных плиток Apple на панораме станет видна.
            XCTAssertLessThan(Int(pixels[i + 2]), 64, "дымка светлее тёмной подложки Apple")
        }
    }

    /// Дымка объёмная, а не плоская: у верха и низа тайла разный цвет.
    func testFillHasDepth() {
        let size = 64
        let pixels = Self.drawn(size: size) { context, rect in
            FogVeilPainter.paint(
                context: context, paths: [], corridorWidth: 90, passes: 8,
                tileRect: rect, depth: .flat
            )
        }
        let top = Int(pixels[(2 * size + 2) * 4 + 2])
        let bottom = Int(pixels[((size - 3) * size + 2) * 4 + 2])
        XCTAssertNotEqual(top, bottom, "заливка плоская — объёма в тумане нет")
    }

    /// Глубина считается от МИРОВОЙ координаты тайла, а не от его собственной:
    /// у двух соседних тайлов общий край обязан совпасть по цвету, иначе на
    /// панораме видна сетка стыков.
    func testDepthIsContinuousAcrossNeighbouringTiles() {
        let span = MKMapSize.world.height / 4096
        let upper = MKMapRect(x: 1_000_000, y: 2_000_000, width: span, height: span)
        let lower = MKMapRect(x: 1_000_000, y: 2_000_000 + span, width: span, height: span)

        let a = FogVeilRenderer.depth(for: upper, lod: .mid)
        let b = FogVeilRenderer.depth(for: lower, lod: .mid)

        XCTAssertEqual(a.bottom, b.top, accuracy: 0.0001,
                       "нижний край верхнего тайла и верхний край нижнего разошлись по цвету")
    }

    // MARK: - Дымка

    /// Пятна сеются на МИРОВОЙ сетке, поэтому стык двух соседних тайлов не
    /// виден: пятно, севшее на границу, обе стороны считают от одних и тех же
    /// координат и рисуют одинаково.
    ///
    /// До правки 15 сентября бесшовность держалась тем, что пятно стояло ровно
    /// в центре тайла и гасло к его краю в ноль, — и ровно это выстраивало
    /// узор правильной сеткой.
    func testHazeMeetsAtTheBorderOfTwoTiles() {
        let size = 64
        let span = FogVeilRenderer.hazeCell(for: .mid)
        let left = MKMapRect(x: 60_000_000, y: 40_000_000, width: span, height: span)
        let right = MKMapRect(x: 60_000_000 + span, y: 40_000_000, width: span, height: span)

        let a = Self.drawnTile(size: size, mapRect: left)
        let b = Self.drawnTile(size: size, mapRect: right)

        for row in 0..<size {
            let edgeA = Int(a[(row * size + size - 1) * 4 + 2])
            let edgeB = Int(b[(row * size) * 4 + 2])
            XCTAssertEqual(
                Double(edgeA), Double(edgeB), accuracy: 3,
                "на строке \(row) правый край левого тайла и левый край правого разошлись: "
                    + "\(edgeA) против \(edgeB) — на панораме это видимая сетка")
        }
    }

    /// Тот же тайл на том же зуме — тот же узор, до пикселя. Иначе каждая
    /// перерисовка (а MapKit перерисовывает тайл по любому поводу) давала бы
    /// мигание там, где должен быть неподвижный туман.
    func testHazeIsDeterministicForTheSameTile() {
        let span = FogVeilRenderer.hazeCell(for: .far)
        let tile = MKMapRect(x: 12_345_678, y: 87_654_321, width: span, height: span)

        XCTAssertEqual(Self.drawnTile(size: 32, mapRect: tile),
                       Self.drawnTile(size: 32, mapRect: tile),
                       "узор дымки изменился между двумя отрисовками одного тайла")
    }

    /// Пятен на тайле НЕСКОЛЬКО и лежат они не в центре: узор обязан быть
    /// неровным по обеим осям. (До правки пятно было одно, всегда в середине.)
    func testHazeIsNotOneBlobInTheMiddle() {
        let cell = FogVeilRenderer.hazeCell(for: .mid)
        var seen = Set<String>()
        for col in Int64(0)..<3 {
            for row in Int64(0)..<3 {
                let blobs = FogVeilPainter.hazeBlobs(col: col, row: row, cell: cell)
                XCTAssertEqual(blobs.count, FogVeilPainter.hazeBlobsPerCell)
                for blob in blobs {
                    XCTAssertTrue(FogVeilPainter.hazeAlphaRange.contains(blob.alpha))
                    // Центр — ВНУТРИ своей ячейки, но не в её середине.
                    let dx = blob.x - Double(col) * cell
                    XCTAssertTrue((0...cell).contains(dx))
                    seen.insert(String(format: "%.4f", dx / cell))
                }
            }
        }
        XCTAssertGreaterThan(seen.count, 6, "пятна выстроились в сетку — узор регулярен")
    }

    /// Верхняя граница светлоты — та же, что у пустого тайла: дымка не имеет
    /// права подняться до уровня, на котором полоса недогруженных плиток Apple
    /// на панораме становится видна.
    func testHazeStaysDarkerThanTheAppleUnderlay() {
        let span = FogVeilRenderer.hazeCell(for: .mid) / 2
        for origin in [40_000_000.0, 133_700_000.0, 220_000_000.0] {
            let pixels = Self.drawnTile(
                size: 48, mapRect: MKMapRect(x: origin, y: origin, width: span, height: span))
            for i in stride(from: 0, to: pixels.count, by: 4) {
                XCTAssertEqual(Int(pixels[i + 3]), 255, "вуаль обязана быть непрозрачной")
                XCTAssertLessThan(Int(pixels[i + 2]), 64, "дымка светлее тёмной подложки Apple")
            }
        }
    }

    // MARK: - Ореол жилки

    /// На стране жилка в 1.6 pt была волоском, а спека обещает светящуюся
    /// вену. Ореол — первый проход тем же янтарём: шире, бледнее, и только там,
    /// где коридор уже ушёл на свой экранный пол.
    func testVeinHaloOnlyExistsWhereTheCorridorIsAtItsFloor() {
        XCTAssertNil(RouteVeinRenderer.halo(for: .fine),
                     "на улице свет даёт сам коридор — второй след вернул бы «страва-ленту»")

        for lod in [RevealedLayer.LOD.mid, .far] {
            guard let halo = RouteVeinRenderer.halo(for: lod) else {
                return XCTFail("на \(lod) ореол обязан быть")
            }
            XCTAssertGreaterThanOrEqual(halo.width, 8)
            XCTAssertLessThanOrEqual(halo.width, 10)
            XCTAssertGreaterThanOrEqual(halo.alpha, 0.10)
            XCTAssertLessThanOrEqual(halo.alpha, 0.14)
            XCTAssertGreaterThan(halo.width, RouteVeinRenderer.width(for: lod),
                                 "ореол не шире сердцевины — это не ореол")
            XCTAssertGreaterThanOrEqual(RouteVeinRenderer.width(for: lod), 2.5,
                                        "сердцевина издали обязана быть толще волоска")
        }
    }

    /// Ореол не имеет права быть шире коридора больше чем на пятую часть:
    /// иначе янтарь ложится на вуаль сплошняком вместо того, чтобы светиться
    /// внутри прочищенного.
    ///
    /// Проверяется СЫРАЯ ширина, до зажима. Прежняя версия этого теста
    /// повторяла внутри себя `min(…, потолок)` из продакшена и потому не могла
    /// упасть никогда: `min(a, b) <= b` истинно всегда.
    func testVeinHaloNeverOutgrowsTheCorridor() {
        let metre = MKMapPointsPerMeterAtLatitude(45.0)
        for zoom: MKZoomScale in [1.5e-3, 1e-3, 3e-4, 1.5e-4, 1e-4, 3e-5, 1e-6] {
            let lod = FogVeilRenderer.lod(for: zoom)
            guard let halo = RouteVeinRenderer.halo(for: lod) else { continue }
            let corridor = Double(FogVeilRenderer.corridorWidth(zoomScale: zoom, metre: metre))
            XCTAssertLessThanOrEqual(
                Double(halo.width / zoom), corridor * 1.2,
                "на зуме \(zoom) ореол (\(halo.width) pt) шире коридора ×1.2 — "
                    + "янтарь ляжет на вуаль сплошняком, и зажим это только спрячет")
        }
    }

    /// Конкретные числа, а не «что-то меньше чего-то»: коридор на среднем и
    /// дальнем уровне стоит на своём экранном полу (12 pt), ×1.2 — это 14.4,
    /// и оба ореола обязаны быть под ним с запасом.
    func testHaloCeilingInScreenPoints() {
        let ceiling = Double(FogVeilRenderer.minVeinPoints) * 1.2
        XCTAssertEqual(ceiling, 14.4, accuracy: 0.001)
        XCTAssertEqual(Double(RouteVeinRenderer.halo(for: .mid)?.width ?? 0), 8)
        XCTAssertEqual(Double(RouteVeinRenderer.halo(for: .far)?.width ?? 0), 10)
        XCTAssertLessThan(Double(RouteVeinRenderer.halo(for: .far)?.width ?? 0), ceiling)
    }

    // MARK: - Дымка не растёт с тайлом

    /// Потолок пятен на тайл. Цикл сеялки идёт по ячейкам, накрывающим тайл, —
    /// и на выведенном в мир «Атласе» (ограничения зума у карты нет) тайл шире
    /// дальней ячейки в восемьдесят раз: пятнадцать тысяч градиентов на ОДИН
    /// тайл. `MapRenderCostTests` этого не видит — он меряет один зум в
    /// середине полосы.
    func testHazeBlobsAreCappedEvenOnAWorldSizedTile() {
        for lod in RevealedLayer.LOD.allCases {
            let cell = FogVeilRenderer.hazeCell(for: lod)
            let world = FogVeilPainter.hazeBlobs(
                in: FogVeilPainter.Haze(world: .world, cell: cell))
            XCTAssertLessThanOrEqual(
                world.count, FogVeilPainter.hazeBlobsPerTile,
                "на мировом тайле (\(lod)) сеялка выдала \(world.count) пятен")

            // И на обычном тайле своего уровня — тоже потолок, не «повезло».
            let tile = MKMapRect(x: 30_000_000, y: 40_000_000, width: cell, height: cell)
            XCTAssertLessThanOrEqual(
                FogVeilPainter.hazeBlobs(in: .init(world: tile, cell: cell)).count,
                FogVeilPainter.hazeBlobsPerTile)
        }
    }

    /// Пятна на тайле всё-таки ЕСТЬ: потолок не имеет права выродиться в
    /// «дымки нет вовсе».
    func testHazeStillDrawsSomethingOnAnOrdinaryTile() {
        let cell = FogVeilRenderer.hazeCell(for: .mid)
        var seen = 0
        for step in 0..<12 {
            let tile = MKMapRect(
                x: 30_000_000 + Double(step) * cell, y: 40_000_000,
                width: cell, height: cell)
            seen += FogVeilPainter.hazeBlobs(in: .init(world: tile, cell: cell)).count
        }
        XCTAssertGreaterThan(seen, 6, "на дюжине тайлов подряд дымки почти нет")
    }

    // MARK: - Индекс собирается вне главного потока и только достижимый

    /// Мёртвых наборов бакетов больше нет: `.fine` никогда не спрашивает грубый
    /// уровень, `.far` — мелкий. Четыре набора на три уровня детали вместо
    /// шести, и самый дорогой из выброшенных — грубые бакеты полноразрядной
    /// геометрии.
    ///
    /// И собирается всё это ВНЕ ГЛАВНОГО ПОТОКА, с фоновой очереди из `init`:
    /// `init` рендерера MapKit зовёт на главном потоке в момент открытия
    /// Атласа. Проверяется именно это, а не «ноль сборок сразу после init» —
    /// прежняя проверка надеялась, что фоновая очередь не успеет, и на
    /// загруженной машине была флейком, а не сторожем.
    func testPathIndexBuildsOnlyReachableBucketSets() {
        let renderer = FogVeilRenderer(veil: FogVeilOverlay(layer: Self.smallLayer()))

        XCTAssertTrue(Self.waitForIndex(renderer),
                      "индекс не собрался за пять секунд: \(renderer.chunkBuilds)")
        XCTAssertEqual(
            renderer.chunkBuilds, 4,
            "четыре достижимых набора (.fine мелкий, .mid оба, .far грубый), ни одним больше")
        XCTAssertFalse(renderer.indexBuiltOnMainThread,
                       "индекс собрался на главном потоке — это хитч на открытии Атласа")

        // Отрисовка индекс не трогает вовсе — ни на одном уровне.
        let context = CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        for zoom: MKZoomScale in [0.01, 0.01, 5e-4, 3e-5] {
            let span = 64 / Double(zoom)
            let origin = MKMapPoint(CLLocationCoordinate2D(latitude: 45.06, longitude: 38.97))
            renderer.draw(
                MKMapRect(x: origin.x - span / 2, y: origin.y - span / 2,
                          width: span, height: span),
                zoomScale: zoom, in: context)
        }
        XCTAssertEqual(renderer.chunkBuilds, 4, "отрисовка собрала индекс заново")
    }

    /// Пока индекс собирается, тайл — сплошная заливка, а НЕ прозрачная дыра.
    /// Это и есть «дешёвый тайл»: карту Apple нельзя показывать ни на кадр.
    func testTileBeforeTheIndexIsReadyIsStillOpaque() {
        let renderer = FogVeilRenderer(veil: FogVeilOverlay(layer: Self.smallLayer()))
        let size = 32
        let pixels = Self.drawn(size: size) { context, rect in
            // Прямо сейчас, не дожидаясь фоновой сборки.
            let zoom: MKZoomScale = 5e-4
            let span = Double(size) / Double(zoom)
            let origin = MKMapPoint(CLLocationCoordinate2D(latitude: 45.06, longitude: 38.97))
            context.saveGState()
            context.scaleBy(x: zoom, y: zoom)
            let mapRect = MKMapRect(x: origin.x - span / 2, y: origin.y - span / 2,
                                    width: span, height: span)
            context.translateBy(x: -renderer.rect(for: mapRect).origin.x,
                                y: -renderer.rect(for: mapRect).origin.y)
            renderer.draw(mapRect, zoomScale: zoom, in: context)
            context.restoreGState()
            _ = rect
        }
        for i in stride(from: 0, to: size * size * 4, by: 4) {
            XCTAssertEqual(Int(pixels[i + 3]), 255, "тайл до готовности индекса прозрачен")
        }
    }

    // MARK: - Инструменты

    /// Маленькая сеть — чтобы фоновая сборка индекса была мгновенной.
    static func smallLayer() -> RevealedLayer {
        let route = (0..<60).map { i in
            CLLocationCoordinate2D(latitude: 45.0 + Double(i) * 0.002, longitude: 38.97)
        }
        return RevealedLayer.build(runs: [route], cellCount: 60, atlas: nil)
    }

    /// Ждёт фоновую сборку индекса, крутя главный цикл: сборка идёт на
    /// `DispatchQueue.global`, и просто `sleep` здесь тоже сработал бы — но
    /// цикл не мешает остальным тестам.
    static func waitForIndex(
        _ renderer: FogVeilRenderer, expected: Int = 4, timeout: TimeInterval = 5
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if renderer.chunkBuilds >= expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return renderer.chunkBuilds >= expected
    }

    /// Рисует один тайл кистью — так же, как это делает рендерер, включая
    /// глубину и дымку от МИРОВЫХ координат тайла.
    private static func drawnTile(size: Int, mapRect: MKMapRect) -> [UInt8] {
        drawn(size: size) { context, rect in
            FogVeilPainter.paint(
                context: context, paths: [], corridorWidth: 90, passes: 8,
                tileRect: rect, depth: FogVeilRenderer.depth(for: mapRect, lod: .mid)
            )
        }
    }

    /// Рисует в свой буфер и отдаёт пиксели копией: указатель на память
    /// массива, переживший `withUnsafeMutableBytes`, — это UB, а тут он ещё и
    /// читается вторым вызовом.
    private static func drawn(size: Int, _ body: (CGContext, CGRect) -> Void) -> [UInt8] {
        let count = size * size * 4
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        data.initialize(repeating: 0, count: count)
        defer { data.deallocate() }
        let context = CGContext(
            data: data, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        body(context, CGRect(x: 0, y: 0, width: size, height: size))
        return Array(UnsafeBufferPointer(start: data, count: count))
    }
}
