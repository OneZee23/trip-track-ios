import XCTest
import MapKit
@testable import TripTrack

/// Кисть разрезана надвое (`fillAndHaze` + `punch`) ради одного числа: слой
/// прозрачности открывается ОДИН раз на растр, а не на каждый тайл. По замеру
/// спайка 15 сентября цену полного кадра держит именно число тайлов — 24 тайла
/// дали 211 мс против 142 мс на пятнадцати при большей площади.
///
/// Разрез имеет право состояться только при одном условии: картинка не
/// изменилась. Плиточный рендерер остаётся откатом (иерархия `MKMapView`
/// приватная и может перестать узнаваться), и два пути обязаны рисовать одно и
/// то же — иначе откат стал бы вторым, другим туманом.
final class FogVeilPainterTests: XCTestCase {

    /// Небольшая проезженная сеть под Краснодаром — форма одного человека.
    private func layer() -> RevealedLayer {
        var runs: [[CLLocationCoordinate2D]] = []
        for pass in 0..<6 {
            let coords = (0..<140).map { i -> CLLocationCoordinate2D in
                let t = Double(i) / 139
                let phase = Double(i) * 0.5 + Double(pass) * 1.3
                return CLLocationCoordinate2D(
                    latitude: 45.00 + 0.010 * t + sin(phase) * 0.00006,
                    longitude: 38.95 + 0.014 * t + cos(phase) * 0.00006
                )
            }
            runs.append(coords)
        }
        return RevealedLayer.build(runs: runs, cellCount: runs.count * 140, atlas: nil)
    }

    /// Индекс в координатах `MKMapPoint` — тот же, что собирает себе вуаль.
    private func index(for revealed: RevealedLayer) -> MapPathIndex {
        let index = MapPathIndex()
        index.prepare(
            source: { revealed.polylines(for: $0) },
            transform: { CGPoint(x: $0.x, y: $0.y) }
        )
        return index
    }

    /// Кадр «улица»: 440 pt видимого на 500 м, запас 1.5×.
    private func frame() -> (rect: MKMapRect, sizePoints: CGSize) {
        let centre = CLLocationCoordinate2D(latitude: 45.005, longitude: 38.957)
        let metre = MKMapPointsPerMeterAtLatitude(centre.latitude)
        let visibleWidth = 500 * metre
        let origin = MKMapPoint(centre)
        let visible = MKMapRect(
            x: origin.x - visibleWidth / 2,
            y: origin.y - visibleWidth * 956 / 440 / 2,
            width: visibleWidth, height: visibleWidth * 956 / 440)
        let rect = FogVeilView.renderRect(visible: visible, margin: FogVeilView.defaultMargin)
        let ppmp = 440 / visible.width
        return (rect, CGSize(width: CGFloat(rect.width * ppmp),
                             height: CGFloat(rect.height * ppmp)))
    }

    // MARK: Один слой прозрачности

    /// Растр с коридорами открывает буфер РОВНО один раз, сколько бы тайлов в
    /// нём ни было.
    func testWholeRasterPunchesInASingleTransparencyLayer() {
        let revealed = layer()
        let (rect, sizePoints) = frame()
        guard let band = FogVeilBitmap.render(
            rect: rect, sizePoints: sizePoints, scale: 1,
            index: index(for: revealed), selected: []
        ) else { return XCTFail("растр обязан собраться") }

        print("[veil] полос тайлов \(band.tiles), слоёв прозрачности \(band.layers)")
        XCTAssertGreaterThan(band.tiles, 4, "мерить нечего: тайлов должно быть много")
        XCTAssertEqual(band.layers, 1, "слой прозрачности обязан открываться один раз на растр")
    }

    /// Растр в стороне от всех своих дорог не открывает слой вовсе — как и
    /// пустой тайл у плиточного рендерера.
    func testRasterWithNoRoadsOpensNoTransparencyLayer() {
        let revealed = layer()
        let far = MKMapRect(origin: MKMapPoint(CLLocationCoordinate2D(latitude: 53, longitude: 45)),
                            size: MKMapSize(width: 20_000, height: 30_000))
        guard let band = FogVeilBitmap.render(
            rect: far, sizePoints: CGSize(width: 400, height: 600), scale: 1,
            index: index(for: revealed), selected: []
        ) else { return XCTFail("растр обязан собраться") }
        XCTAssertEqual(band.layers, 0)
    }

    // MARK: Непрозрачность

    /// В растре НЕ ДОЛЖНО быть ни одного полупрозрачного пикселя, кроме
    /// прожжённых коридоров.
    ///
    /// Стык тайлов — это место, где полупрозрачность заводится сама: клип
    /// сглаживается, и два соседних тайла оставляют на общей границе по
    /// половине пикселя. У плиточного рендерера этого не видно (соседа рисует
    /// MapKit в общий буфер), а в растре сквозь такую линию светит живая
    /// карта Apple — ровно то, что туман обязан прятать.
    func testRasterHasNoSeamsBetweenTiles() {
        // Растр ЗАВЕДОМО мимо сети: коридоров в нём нет вовсе, поэтому любая
        // полупрозрачность в нём — шов, а не перьевой край дыры.
        let revealed = layer()
        let far = MKMapRect(
            origin: MKMapPoint(CLLocationCoordinate2D(latitude: 53, longitude: 45)),
            size: MKMapSize(width: 40_000, height: 90_000))
        let sizePoints = CGSize(width: 660, height: 1_434)
        guard let band = FogVeilBitmap.render(
            rect: far, sizePoints: sizePoints, scale: 1,
            index: index(for: revealed), selected: []
        ) else { return XCTFail("растр обязан собраться") }
        let grid = FogVeilBitmap.grid(sizePoints: sizePoints)
        XCTAssertGreaterThan(grid.cols * grid.rows, 4, "мерить нечего: тайлов должно быть много")

        // Картинка на пиксель выше логической полосы — это припуск, который
        // накрывает стык с соседней полосой; сама полоса кончается раньше.
        let width = band.image.width
        let height = band.image.height
        guard let data = pixels(of: band.image, width: width, height: height)
        else { return XCTFail("пиксели обязаны прочитаться") }

        var seams: [(Int, Int)] = []
        for y in 0..<(height - 1) {
            for x in 0..<width where data[(y * width + x) * 4 + 3] != 255 {
                seams.append((x, y))
            }
        }
        print("[veil] щелей в туман: \(seams.count), первые "
              + "\(seams.prefix(5).map { "\($0.0)×\($0.1)" }.joined(separator: " "))")
        XCTAssertTrue(seams.isEmpty, "на стыке тайлов остаётся щель в туман")
    }

    // MARK: Равенство с откатом

    /// Растр целиком и тот же кадр, собранный ПЛИТОЧНЫМ рендерером тайл за
    /// тайлом, — одна и та же картинка.
    ///
    /// Допуск не нулевой, и обе его причины названы:
    /// 1. ширина коридора у растра берётся по широте середины полосы, а у
    ///    рендерера — по широте каждого тайла (на кадре телефона это доли
    ///    промилле);
    /// 2. плиточный путь клипует каждый тайл, и на границах клипа остаётся
    ///    пиксель сглаживания — та самая сетка, из-за которой растр и делался.
    func testWholeRasterMatchesTheTiledFallback() {
        let revealed = layer()
        let (rect, sizePoints) = frame()
        let prepared = index(for: revealed)
        guard let band = FogVeilBitmap.render(
            rect: rect, sizePoints: sizePoints, scale: 1, index: prepared, selected: []
        ) else { return XCTFail("растр обязан собраться") }

        // Картинка на пиксель выше логической полосы (припуск на стык), и
        // читать её надо в СВОЁМ размере: вписав её в контекст на пиксель
        // ниже, мы добавили бы к расхождению собственный подпиксельный сдвиг.
        let width = band.image.width
        let height = band.image.height
        guard let mine = pixels(of: band.image, width: width, height: height),
              let theirs = tiledReference(rect: rect, sizePoints: sizePoints,
                                          revealed: revealed, width: width, height: height)
        else { return XCTFail("обе картинки обязаны собраться") }

        var worse = 0
        var total = 0.0
        // Последний ряд — тот самый припуск, у эталона его нет.
        let compared = (height - 1) * width * 4
        for i in stride(from: 0, to: compared, by: 4) {
            for channel in 0..<3 {
                let delta = abs(Int(mine[i + channel]) - Int(theirs[i + channel]))
                total += Double(delta)
                if delta > 8 { worse += 1; break }
            }
        }
        let count = compared / 4
        let share = Double(worse) / Double(count)
        let mean = total / Double(count * 3)
        print(String(format: "[veil] растр против тайлов: расходятся %.3f %% пикселей, "
                     + "средняя разница %.3f уровня", share * 100, mean))
        XCTAssertLessThan(share, 0.02,
                          "растр и плиточный откат обязаны рисовать одно и то же")
        XCTAssertLessThan(mean, 1.5, "средняя разница по каналу — меньше полутора уровней")
    }

    // MARK: Круг подсказки

    /// Кадр ЗАВЕДОМО мимо сети: коридоров нет, поэтому любое отличие от
    /// пустого тумана — это и есть кольцо подсказки.
    private func emptyFrame() -> (rect: MKMapRect, sizePoints: CGSize) {
        let rect = MKMapRect(
            origin: MKMapPoint(CLLocationCoordinate2D(latitude: 53, longitude: 45)),
            size: MKMapSize(width: 60_000, height: 60_000))
        return (rect, CGSize(width: 600, height: 600))
    }

    /// Кольцо стоит на СВОЁМ радиусе, и за ним туман не тронут.
    ///
    /// Это и есть проверка «круг не растёт вместе с отдалением»: радиус задан
    /// в точках карты, то есть в земле, и на любом масштабе кольцо ложится на
    /// одну и ту же окружность. До 0.7.0 круг рисовал слой аннотации в точках
    /// ЭКРАНА, и во время щипка он оставался прежним кружком.
    func testEngravedRingLandsOnItsRadiusAndLeavesTheFogBeyondAlone() {
        let revealed = layer()
        let (rect, sizePoints) = emptyFrame()
        let prepared = index(for: revealed)
        let ppmp = Double(sizePoints.width) / rect.width
        let radiusPixels = 180.0
        let hint = FogVeilPainter.EngravedHint(
            centre: CGPoint(x: rect.midX, y: rect.midY),
            radius: CGFloat(radiusPixels / ppmp))

        guard let plain = FogVeilBitmap.render(
            rect: rect, sizePoints: sizePoints, scale: 1,
            index: prepared, selected: []),
            let ringed = FogVeilBitmap.render(
                rect: rect, sizePoints: sizePoints, scale: 1,
                index: prepared, selected: [], hints: [hint])
        else { return XCTFail("оба растра обязаны собраться") }

        let width = ringed.image.width, height = ringed.image.height
        guard let base = pixels(of: plain.image, width: width, height: height),
              let drawn = pixels(of: ringed.image, width: width, height: height)
        else { return XCTFail("пиксели обязаны прочитаться") }

        func differences(atRadius radius: Double) -> Int {
            var count = 0
            for step in 0..<720 {
                let angle = Double(step) / 720 * 2 * .pi
                let x = Int((Double(width) / 2 + cos(angle) * radius).rounded())
                let y = Int((Double(height) / 2 + sin(angle) * radius).rounded())
                guard x >= 0, x < width, y >= 0, y < height else { continue }
                let i = (y * width + x) * 4
                if (0..<3).contains(where: { abs(Int(base[i + $0]) - Int(drawn[i + $0])) > 3 }) {
                    count += 1
                }
            }
            return count
        }

        let onRing = differences(atRadius: radiusPixels)
        let beyond = differences(atRadius: radiusPixels * 1.3)
        print("[veil] кольцо подсказки: на радиусе \(onRing) точек из 720, за ним \(beyond)")
        XCTAssertGreaterThan(onRing, 100, "кольцо обязано лечь на свой радиус")
        XCTAssertEqual(beyond, 0, "за кольцом туман обязан остаться нетронутым")
    }

    /// Кольцо — след, а не элемент управления: непрозрачность под потолком.
    ///
    /// Владелец на устройстве: «синий круг сильно выделяется — криво и страшно
    /// в тумане». Полная бирюза загадки (`SealPainter.ring(for: .riddle)`) на
    /// почти чёрной вуали — самое яркое пятно экрана.
    func testHintRingStaysFaint() {
        XCTAssertLessThanOrEqual(FogVeilPainter.hintRingAlpha, 0.45,
                                 "кольцо подсказки не имеет права спорить с печатью находки")
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var hue: CGFloat = 0, alpha: CGFloat = 0
        FogVeilPainter.hintRingColor.getHue(&hue, saturation: &saturation,
                                            brightness: &brightness, alpha: &alpha)
        var riddleSaturation: CGFloat = 0
        SealPainter.ring(for: .riddle).getHue(&hue, saturation: &riddleSaturation,
                                              brightness: &brightness, alpha: &alpha)
        XCTAssertLessThan(saturation, riddleSaturation,
                          "цвет кольца обязан быть ОБЕСЦВЕЧЕННОЙ бирюзой, а не бирюзой")
    }

    /// Постер «Поделиться» подсказок не получает — ни одной строкой.
    ///
    /// Правило волны 4 записано словами («на постер попадает только
    /// найденное»), а держится оно ровно тем, что у `FogVeilBitmap.render`
    /// круги — параметр по умолчанию пустой, и постер его не заполняет.
    /// Поведенческого теста у этого нет: нарисовать подсказку постер может
    /// только новой строкой кода, и ловить её надо в диффе.
    func testPosterNeverAsksForHints() {
        let poster = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TripTrack/Views/MyMap/AtlasSharePoster.swift")
        guard let source = try? String(contentsOf: poster, encoding: .utf8) else {
            return XCTFail("исходник постера обязан читаться")
        }
        XCTAssertFalse(source.contains("hints:"),
                       "постер не имеет права передавать круги подсказок — это ответ на загадку")
    }

    // MARK: Ореол, облака и рваный край

    /// Кадр вокруг ОДНОЙ прямой дороги: по нему меряется профиль коридора
    /// поперёк, а вдоль — рваность его края.
    ///
    /// Синтетический, а не настоящий растр, и вот почему: `FogVeilBitmap`
    /// рисует поверх коридора ещё и жилку сети, то есть возвращает альфу в
    /// самую сердцевину. Вопрос «прочищена ли сердцевина» — про КИСТЬ, и
    /// спрашивать его надо у кисти.
    private func corridorRaster(
        lod: RevealedLayer.LOD, metresPerPoint: Double, withClouds: Bool, side: Int = 400
    ) -> (pixels: [UInt8], side: Int, halfWidthPixels: Double)? {
        let centre = CLLocationCoordinate2D(latitude: 45, longitude: 38.95)
        let metre = MKMapPointsPerMeterAtLatitude(centre.latitude)
        let span = Double(side) * metresPerPoint * metre
        let origin = MKMapPoint(centre)
        let rect = MKMapRect(x: origin.x - span / 2, y: origin.y - span / 2,
                             width: span, height: span)
        let zoomScale = MKZoomScale(Double(side) / span)
        XCTAssertEqual(FogVeilRenderer.lod(for: zoomScale), lod,
                       "кадр обязан попасть в проверяемый уровень детали")
        let width = FogVeilRenderer.corridorWidth(zoomScale: zoomScale, metre: metre)
        let passes = FogVeilRenderer.passes(forScreenWidth: width * CGFloat(zoomScale), lod: lod)

        let road = CGMutablePath()
        road.move(to: CGPoint(x: rect.minX - rect.width, y: rect.midY))
        road.addLine(to: CGPoint(x: rect.maxX + rect.width, y: rect.midY))

        var data = [UInt8](repeating: 0, count: side * side * 4)
        let ok: Bool = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return false }
            context.translateBy(x: 0, y: CGFloat(side))
            context.scaleBy(x: 1, y: -1)
            context.scaleBy(x: CGFloat(zoomScale), y: CGFloat(zoomScale))
            context.translateBy(x: CGFloat(-rect.minX), y: CGFloat(-rect.minY))
            let box = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
            FogVeilPainter.paint(
                context: context, paths: [road], corridorWidth: width, passes: passes,
                tileRect: box, depth: FogVeilRenderer.depth(for: rect, lod: lod),
                clouds: withClouds
                    ? FogVeilRenderer.clouds(for: rect, rect: box, lod: lod)
                    : nil)
            return true
        }
        guard ok else { return nil }
        return (data, side, Double(width) / 2 * Double(zoomScale))
    }

    /// Три точки шкалы: улица, город, страна.
    private static let corridorScales: [(RevealedLayer.LOD, Double)] = [
        (.fine, 2), (.mid, 200), (.far, 1_500),
    ]

    /// Сердцевина коридора прочищена ПОЛНОСТЬЮ на всех трёх уровнях детали.
    ///
    /// Это и есть граница правила «рваный край»: клубиться обязан КРАЙ
    /// открытого, а не само открытое. Держит его не аккуратность, а
    /// построение — последний проход пера идёт с альфой 1, — и проверять это
    /// надо на всех трёх уровнях: число проходов у них разное (14/8 против 4),
    /// и на четырёх ступенях ошибку разбиения было бы видно первой.
    func testCorridorCoreIsFullyClearOnEveryLod() {
        for (lod, metresPerPoint) in Self.corridorScales {
            guard let shot = corridorRaster(
                lod: lod, metresPerPoint: metresPerPoint, withClouds: true)
            else { return XCTFail("растр обязан собраться (\(lod))") }
            let mid = shot.side / 2
            for x in stride(from: 4, to: shot.side - 4, by: 13) {
                let alpha = shot.pixels[(mid * shot.side + x) * 4 + 3]
                XCTAssertEqual(alpha, 0,
                               "сердцевина коридора на \(lod) закрыта туманом в x = \(x)")
            }
        }
    }

    /// За полутора ореолами туман НЕ ТРОНУТ.
    ///
    /// Маска облаков умеет только оставлять туман там, где перо его снимало;
    /// добавить открытого за пределами ореола она не имеет права — иначе
    /// «открыто» перестало бы значить «я здесь был».
    func testFogBeyondTheHaloIsUntouched() {
        for (lod, metresPerPoint) in Self.corridorScales {
            guard let shot = corridorRaster(
                lod: lod, metresPerPoint: metresPerPoint, withClouds: true)
            else { return XCTFail("растр обязан собраться (\(lod))") }
            let mid = shot.side / 2
            let reach = Int((shot.halfWidthPixels * 1.45).rounded(.up)) + 1
            guard mid - reach > 2 else { return XCTFail("кадр мал для замера (\(lod))") }
            for row in [mid - reach, mid + reach, 2, shot.side - 3] {
                for x in stride(from: 4, to: shot.side - 4, by: 17) {
                    let alpha = shot.pixels[(row * shot.side + x) * 4 + 3]
                    XCTAssertEqual(alpha, 255,
                                   "туман за ореолом тронут: \(lod), ряд \(row), x = \(x)")
                }
            }
        }
    }

    /// Край коридора КЛУБИТСЯ: вдоль прямой дороги плотность перьевой ленты
    /// гуляет, а без облаков она одинакова до уровня.
    ///
    /// Сравнение с «без облаков» тут обязательно. «Значения вдоль края
    /// разные» само по себе доказывает только то, что мы взяли неровную
    /// дорогу; доказательство даёт именно РАЗНИЦА между двумя кистями на
    /// одной и той же прямой.
    func testCorridorEdgeIsRaggedOnlyWithClouds() {
        for (lod, metresPerPoint) in Self.corridorScales {
            guard let ragged = corridorRaster(
                    lod: lod, metresPerPoint: metresPerPoint, withClouds: true),
                  let plain = corridorRaster(
                    lod: lod, metresPerPoint: metresPerPoint, withClouds: false)
            else { return XCTFail("оба растра обязаны собраться (\(lod))") }

            // Размах берётся по всей перьевой ленте, а не на одной высоте:
            // где именно модуляция сильнее всего, зависит от числа проходов
            // пера (их 14, 8 или 4), и прибивать замер к одной строке значило
            // бы мерить на трёх уровнях три разных места ленты.
            func spread(_ shot: (pixels: [UInt8], side: Int, halfWidthPixels: Double)) -> Int {
                var worst = 0
                for share in stride(from: 0.55, through: 1.0, by: 0.05) {
                    let row = shot.side / 2 + Int((shot.halfWidthPixels * share).rounded())
                    guard row > 0, row < shot.side else { continue }
                    var low = 255, high = 0
                    for x in stride(from: 8, to: shot.side - 8, by: 3) {
                        let alpha = Int(shot.pixels[(row * shot.side + x) * 4 + 3])
                        low = min(low, alpha)
                        high = max(high, alpha)
                    }
                    worst = max(worst, high - low)
                }
                return worst
            }
            let withClouds = spread(ragged)
            let without = spread(plain)
            print("[veil] край на \(lod): размах с облаками \(withClouds), без них \(without)")
            XCTAssertLessThanOrEqual(without, 2,
                                     "без облаков край прямой дороги обязан быть ровным (\(lod))")
            XCTAssertGreaterThan(withClouds, 30,
                                 "с облаками край обязан клубиться (\(lod))")
        }
    }

    /// Облака ложатся на МИРОВУЮ сетку: два соседних куска, посчитавших узор
    /// каждый от своих координат, обязаны нарисовать его в одном месте земли.
    ///
    /// Иначе он «плывёт» при панораме и рвётся на швах тайлов и полос — то
    /// самое, из-за чего дымка в 0.7.0 сеется мировой сеялкой, а не тайлом.
    func testCloudsAreAnchoredToTheWorldNotToThePiece() {
        guard let images = CloudTexture.shared.prepare() else {
            return XCTFail("текстура обязана собраться")
        }
        let centre = MKMapPoint(CLLocationCoordinate2D(latitude: 45, longitude: 38.95))
        let cell = FogVeilRenderer.hazeCell(for: .fine)
        let span = cell / 4
        let world = MKMapRect(x: centre.x, y: centre.y, width: span, height: span)
        let side = 200

        func paint(offsetPieces: Int) -> [UInt8] {
            // Кусок ТОГО ЖЕ куска мира, но нарисованный как часть большего:
            // мировые координаты те же, координаты контекста — свои.
            var data = [UInt8](repeating: 0, count: side * side * 4)
            data.withUnsafeMutableBytes { bytes in
                guard let context = CGContext(
                    data: bytes.baseAddress, width: side, height: side,
                    bitsPerComponent: 8, bytesPerRow: side * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                        | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
                let scale = CGFloat(Double(side) / span)
                context.translateBy(x: 0, y: CGFloat(side))
                context.scaleBy(x: 1, y: -1)
                context.scaleBy(x: scale, y: scale)
                context.translateBy(x: CGFloat(-world.minX), y: CGFloat(-world.minY))
                let box = CGRect(x: world.minX, y: world.minY,
                                 width: world.width, height: world.height)
                // Первый рисует кусок как самостоятельный, второй — как часть
                // куска, начинающегося на `offsetPieces` шагов левее и выше.
                let bigger = MKMapRect(
                    x: world.minX - span * Double(offsetPieces),
                    y: world.minY - span * Double(offsetPieces),
                    width: span * Double(offsetPieces + 1),
                    height: span * Double(offsetPieces + 1))
                let biggerBox = CGRect(
                    x: bigger.minX, y: bigger.minY, width: bigger.width, height: bigger.height)
                context.setFillColor(UIColor.white.cgColor)
                context.fill(box)
                FogVeilPainter.fillAndHaze(
                    context: context, tile: box,
                    depth: FogVeilPainter.Depth(top: 0.5, bottom: 0.5, haze: nil),
                    clouds: FogVeilPainter.CloudLay(
                        world: bigger, rect: biggerBox, cell: cell,
                        density: images.density, mask: images.mask))
            }
            return data
        }

        let alone = paint(offsetPieces: 0)
        let inside = paint(offsetPieces: 3)
        var worst = 0
        for i in stride(from: 0, to: alone.count, by: 4) {
            worst = max(worst, abs(Int(alone[i + 1]) - Int(inside[i + 1])))
        }
        print("[clouds] узор от разных кусков расходится на \(worst) уровня")
        XCTAssertLessThanOrEqual(worst, 2,
                                 "облака посчитаны от куска, а не от мира — узор поплывёт")
    }

    // MARK: Границы и заливка регионов

    /// Два соседа по 0.95° долготы каждый: западный посещён, восточный — нет.
    private func twoRegions() -> RegionPathIndex {
        func box(_ minLon: Double, _ maxLon: Double) -> [Double] {
            [44, minLon, 44, maxLon, 46, maxLon, 46, minLon]
        }
        let index = RegionPathIndex()
        index.prepare(outlines: [
            RegionOutline(id: "W", isCountry: false, rings: [box(38.0, 38.95)]),
            RegionOutline(id: "E", isCountry: false, rings: [box(38.95, 39.9)]),
        ])
        return index
    }

    /// Кадр вокруг границы этих двух регионов, на заданных метрах на точку.
    private func regionFrame(metresPerPoint: Double, side: CGFloat = 400)
    -> (rect: MKMapRect, sizePoints: CGSize) {
        let centre = CLLocationCoordinate2D(latitude: 45, longitude: 38.95)
        let metre = MKMapPointsPerMeterAtLatitude(centre.latitude)
        let span = Double(side) * metresPerPoint * metre
        let origin = MKMapPoint(centre)
        return (MKMapRect(x: origin.x - span / 2, y: origin.y - span / 2,
                          width: span, height: span),
                CGSize(width: side, height: side))
    }

    /// Средняя «теплота» куска картинки: насколько красного больше синего.
    ///
    /// Именно разность каналов, а не яркость: вуаль синеватая
    /// (`veilColorTop` #0c0d12), заливка посещённого — терракота #C2452B, и
    /// светлее от неё картинка почти не становится.
    private func warmth(
        _ pixels: [UInt8], width: Int, height: Int, column: ClosedRange<Double>
    ) -> Double {
        var sum = 0.0
        var count = 0
        for y in stride(from: height / 8, to: height / 3, by: 3) {
            let from = Int(Double(width) * column.lowerBound)
            let to = Int(Double(width) * column.upperBound)
            for x in stride(from: from, to: to, by: 3) {
                let i = (y * width + x) * 4
                sum += Double(pixels[i + 2]) - Double(pixels[i])
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) : 0
    }

    /// Посещённый регион ТЕПЛЕЕ непосещённого — и это единственное, чем они на
    /// карте отличаются: контур есть у обоих.
    func testVisitedRegionIsWarmerThanTheUnvisitedOne() {
        let (rect, sizePoints) = regionFrame(metresPerPoint: 200)
        let index = MapPathIndex()
        index.prepare(source: { _ in [] }, transform: { CGPoint(x: $0.x, y: $0.y) })
        guard let band = FogVeilBitmap.render(
            rect: rect, sizePoints: sizePoints, scale: 1, index: index, selected: [],
            regions: twoRegions(), visited: ["W"])
        else { return XCTFail("растр обязан собраться") }
        let width = band.image.width, height = band.image.height
        guard let pixels = pixels(of: band.image, width: width, height: height)
        else { return XCTFail("пиксели обязаны прочитаться") }

        let visited = warmth(pixels, width: width, height: height, column: 0.15...0.40)
        let plain = warmth(pixels, width: width, height: height, column: 0.60...0.85)
        print(String(format: "[regions] теплота: посещённый %.2f, непосещённый %.2f",
                     visited, plain))
        XCTAssertGreaterThan(visited, plain + 3,
                             "заливку посещённого региона не отличить от тумана")
    }

    /// На улице границ НЕТ ни одной: их показывает сама карта Apple, и наши
    /// легли бы вторым контуром рядом с её.
    func testFineZoomDrawsNoBorders() {
        let (rect, sizePoints) = regionFrame(metresPerPoint: 2)
        let index = MapPathIndex()
        index.prepare(source: { _ in [] }, transform: { CGPoint(x: $0.x, y: $0.y) })
        guard let bare = FogVeilBitmap.render(
                rect: rect, sizePoints: sizePoints, scale: 1, index: index, selected: []),
              let asked = FogVeilBitmap.render(
                rect: rect, sizePoints: sizePoints, scale: 1, index: index, selected: [],
                regions: twoRegions(), visited: ["W"])
        else { return XCTFail("оба растра обязаны собраться") }
        XCTAssertEqual(FogVeilRenderer.lod(
            for: MKZoomScale(sizePoints.width / CGFloat(rect.width))), .fine)

        let width = asked.image.width, height = asked.image.height
        guard let without = pixels(of: bare.image, width: width, height: height),
              let with = pixels(of: asked.image, width: width, height: height)
        else { return XCTFail("пиксели обязаны прочитаться") }
        XCTAssertEqual(without, with, "на масштабе улицы наших границ быть не должно")
    }

    /// И заливка, и граница живут ПОД коридорами: перо прожигает их вместе с
    /// туманом, поэтому внутри открытого человек видит границы Apple, а
    /// снаружи — наши. Двойных линий не остаётся.
    func testCorridorsBurnThroughTheRegionFillToo() {
        let revealed = layer()
        let (rect, sizePoints) = frame()
        let prepared = index(for: revealed)
        // Регион, накрывающий весь кадр, и он посещён.
        let regions = RegionPathIndex()
        regions.prepare(outlines: [RegionOutline(
            id: "W", isCountry: false, rings: [[44, 38, 44, 40, 46, 40, 46, 38]])])
        guard let band = FogVeilBitmap.render(
            rect: rect, sizePoints: sizePoints, scale: 1, index: prepared, selected: [],
            regions: regions, visited: ["W"])
        else { return XCTFail("растр обязан собраться") }

        let width = band.image.width, height = band.image.height
        guard let data = pixels(of: band.image, width: width, height: height)
        else { return XCTFail("пиксели обязаны прочитаться") }
        var clear = 0
        for i in stride(from: 0, to: (height - 1) * width * 4, by: 4) where data[i + 3] == 0 {
            clear += 1
        }
        print("[regions] полностью прожжённых пикселей под заливкой: \(clear)")
        XCTAssertGreaterThan(clear, 500,
                             "заливка региона легла ПОВЕРХ коридоров и закрыла открытое")
    }

    // MARK: Внутри

    /// Тот же кадр настоящим `FogVeilRenderer`, тайл за тайлом, с клипом на
    /// каждый тайл — ровно так его зовёт MapKit.
    private func tiledReference(
        rect: MKMapRect, sizePoints: CGSize, revealed: RevealedLayer,
        width: Int, height: Int
    ) -> [UInt8]? {
        let renderer = FogVeilRenderer(veil: FogVeilOverlay(layer: revealed))
        guard FogVeilRendererTests.waitForIndex(renderer) else { return nil }
        // Жилку растр рисует сам (оверлеем она лежала бы ПОД вуалью), поэтому
        // в откате её тоже надо нарисовать — на экране это те же два оверлея
        // один над другим.
        let vein = RouteVeinRenderer(vein: RouteVeinOverlay(layer: revealed))
        let deadline = Date().addingTimeInterval(5)
        while vein.chunkBuilds < 4, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }

        var data = [UInt8](repeating: 0, count: width * height * 4)
        let ok: Bool = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return false }

            let zoomScale = MKZoomScale(sizePoints.width / CGFloat(rect.width))
            let origin = renderer.rect(for: rect).origin
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.scaleBy(x: CGFloat(zoomScale), y: CGFloat(zoomScale))
            context.translateBy(x: -origin.x, y: -origin.y)

            let grid = FogVeilBitmap.grid(sizePoints: sizePoints)
            let tileW = rect.width / Double(grid.cols)
            let tileH = rect.height / Double(grid.rows)
            for col in 0..<grid.cols {
                for row in 0..<grid.rows {
                    let tile = MKMapRect(x: rect.minX + Double(col) * tileW,
                                         y: rect.minY + Double(row) * tileH,
                                         width: tileW, height: tileH)
                    let local = renderer.rect(for: tile)
                    context.saveGState()
                    context.clip(to: local)
                    renderer.draw(tile, zoomScale: zoomScale, in: context)
                    vein.draw(tile, zoomScale: zoomScale, in: context)
                    context.restoreGState()
                }
            }
            return true
        }
        return ok ? data : nil
    }

    private func pixels(of image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let ok: Bool = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? data : nil
    }
}
