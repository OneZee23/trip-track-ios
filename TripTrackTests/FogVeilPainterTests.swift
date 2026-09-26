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

    // MARK: Швы

    /// Мгла ОДНОРОДНА: на стыках тайлов нет ни щели, ни тёмной линии.
    ///
    /// Пока туман был непрозрачным, шов выглядел дырой в карту Apple, и
    /// закрывали его нахлёстом в полпикселя. С «ночной картой» мгла
    /// полупрозрачна, и тот же нахлёст стал складывать две альфы — шов из
    /// дыры превратился в тёмную решётку по всем границам тайлов. Поэтому
    /// припуска больше нет, а клип рисуется с выключенным сглаживанием:
    /// прямоугольники соседей сходятся пиксель в пиксель. Проверяется ровно
    /// это — РАЗБРОС альфы, а не её величина.
    func testRasterHasNoSeamsBetweenTiles() {
        let originalPalette = FogVeilPainter.palette
        let hadCloudTexture = CloudTexture.shared.ready != nil
        defer {
            FogVeilPainter.palette = originalPalette
            CloudTexture.shared.forget()
            if hadCloudTexture { CloudTexture.shared.prepare() }
        }
        for (name, palette) in [("night", FogVeilPainter.Palette.night), ("mist", .mist)] {
            FogVeilPainter.palette = palette
            CloudTexture.shared.forget()
            CloudTexture.shared.prepare()
            // Растр ЗАВЕДОМО мимо сети: коридоров в нём нет вовсе, поэтому любая
            // неоднородность — это шов, а не перьевой край дыры.
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

            let width = band.image.width, height = band.image.height
            guard let data = pixels(of: band.image, width: width, height: height)
            else { return XCTFail("пиксели обязаны прочитаться") }

            // Шов — это СКАЧОК на известной границе, а не разброс по кадру:
            // рампа глубины и облака живут теперь в прозрачности, и мгла честно
            // гуляет (замер: 154…197). Поэтому меряется то же, чем меряется шов
            // текстуры облаков: перепад через границу тайла против перепада между
            // любыми соседними столбцами внутри него.
            func alpha(_ x: Int, _ y: Int) -> Double {
                Double(data[(y * width + x) * 4 + 3])
            }
            func meanJump(at columns: [Int]) -> Double {
                var sum = 0.0
                var count = 0
                for x in columns where x > 0 && x < width - 1 {
                    for y in stride(from: 4, to: height - 6, by: 3) {
                        sum += abs(alpha(x, y) - alpha(x - 1, y))
                        count += 1
                    }
                }
                return count > 0 ? sum / Double(count) : 0
            }
            let borders = (1..<grid.cols).map { $0 * width / grid.cols }
            let inside = borders.map { $0 + max(3, width / grid.cols / 3) }
            let onSeam = meanJump(at: borders)
            let ordinary = meanJump(at: inside)
            print(String(format: "[veil] перепад на границе тайла %.3f, внутри %.3f", onSeam, ordinary))
            XCTAssertLessThan(onSeam, max(ordinary * 3, 1.5),
                              "на стыке тайлов мгла рвётся — это шов")

            var low = 255, high = 0
            for y in 0..<(height - 1) {
                for x in 0..<width {
                    let a = Int(data[(y * width + x) * 4 + 3])
                    low = min(low, a); high = max(high, a)
                }
            }
            print("[veil] альфа мглы \(low)…\(high)")
            // The ramp varies the base alpha by ±0.04. Clouds then compose
            // over it as a + (1 - a) × cloudAlpha. Both palettes must stay
            // inside their own opacity bounds; using the old night-only 215
            // ceiling would reject the authored 87% light mist.
            let spread = Double(FogVeilPainter.veilAlphaSpread)
            let baseMin = palette.opacityRange.lowerBound - spread
            let baseMax = palette.opacityRange.lowerBound + spread
            let composedMax = baseMax + (1 - baseMax) * CloudTexture.cloudTopUp
            XCTAssertGreaterThanOrEqual(Double(low), baseMin * 255 - 2,
                                        "\(name): an alpha gap makes the map too visible")
            XCTAssertLessThanOrEqual(Double(high), composedMax * 255 + 2,
                                     "\(name): overlapping tiles make the fog too opaque")
        }
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
        // Both paths need the same prepared texture. The tiled renderer
        // prepares it at init; the bitmap's caller owns that preparation.
        CloudTexture.shared.prepare()
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

    /// На карте страны кольца НЕТ вовсе.
    ///
    /// Три круга по тридцать километров на `.far` перекрываются в одно пятно,
    /// и «след на тумане» читается кляксой — владелец на устройстве 17 сен:
    /// «сильно много внимания на себя берут секреты и кружки вокруг них».
    /// Счёт подсказок на этом масштабе несёт строка под «Атласом», а не
    /// геометрия.
    func testEngravedRingIsGoneAtCountryZoom() {
        XCTAssertFalse(FogVeilPainter.showsHints(lod: .far))
        XCTAssertTrue(FogVeilPainter.showsHints(lod: .mid))
        XCTAssertTrue(FogVeilPainter.showsHints(lod: .fine))

        let revealed = layer()
        let sizePoints = CGSize(width: 600, height: 600)
        // Мир в кадре: 6 000 000 точек карты на 600 pt — `zoomScale` 1e-4, то
        // есть `.far` (`FogVeilRenderer.lod(for:)`).
        let rect = MKMapRect(
            origin: MKMapPoint(CLLocationCoordinate2D(latitude: 53, longitude: 45)),
            size: MKMapSize(width: 6_000_000, height: 6_000_000))
        XCTAssertEqual(
            FogVeilRenderer.lod(for: MKZoomScale(sizePoints.width / CGFloat(rect.width))), .far)
        let prepared = index(for: revealed)
        let hint = FogVeilPainter.EngravedHint(
            centre: CGPoint(x: rect.midX, y: rect.midY), radius: CGFloat(rect.width / 4))

        guard let plain = FogVeilBitmap.render(
            rect: rect, sizePoints: sizePoints, scale: 1, index: prepared, selected: []),
            let ringed = FogVeilBitmap.render(
                rect: rect, sizePoints: sizePoints, scale: 1, index: prepared,
                selected: [], hints: [hint])
        else { return XCTFail("оба растра обязаны собраться") }

        let width = ringed.image.width, height = ringed.image.height
        guard let base = pixels(of: plain.image, width: width, height: height),
              let drawn = pixels(of: ringed.image, width: width, height: height)
        else { return XCTFail("пиксели обязаны прочитаться") }
        XCTAssertEqual(base, drawn, "на карте страны подсказка не рисует ни пикселя")
    }

    /// Выбранное кольцо ярче обычного, и тёмного ободка внутри нет ни у того,
    /// ни у другого.
    ///
    /// Ободок делал круг «вдавленным» и стоил ему четырёх точек толщины — то
    /// есть ровно того внимания, которое с подсказки сняли. Яркость выбранного
    /// — единственный отклик на нажатие: карточка открылась поверх карты, и
    /// найти в тумане тот самый круг больше нечем.
    func testSelectedRingBurnsBrighterAndNeitherHasARim() {
        XCTAssertEqual(FogVeilPainter.hintRingAlpha, 0.18, accuracy: 0.001)
        XCTAssertEqual(FogVeilPainter.hintRingSelectedAlpha, 0.45, accuracy: 0.001)
        XCTAssertEqual(FogVeilPainter.hintRingWidthPoints, 1)
        XCTAssertLessThan(FogVeilPainter.hintRingAlpha,
                          FogVeilPainter.hintRingSelectedAlpha)

        let revealed = layer()
        let (rect, sizePoints) = emptyFrame()
        let prepared = index(for: revealed)
        let ppmp = Double(sizePoints.width) / rect.width
        let radiusPixels = 180.0
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = CGFloat(radiusPixels / ppmp)

        func raster(_ hints: [FogVeilPainter.EngravedHint]) -> [UInt8]? {
            guard let band = FogVeilBitmap.render(
                rect: rect, sizePoints: sizePoints, scale: 1,
                index: prepared, selected: [], hints: hints) else { return nil }
            return pixels(of: band.image, width: band.image.width, height: band.image.height)
        }

        guard let plain = raster([]),
              let quiet = raster([FogVeilPainter.EngravedHint(centre: centre, radius: radius)]),
              let loud = raster([FogVeilPainter.EngravedHint(
                  centre: centre, radius: radius, selected: true)])
        else { return XCTFail("три растра обязаны собраться") }

        let width = Int(sizePoints.width)
        func deviation(from base: [UInt8], in drawn: [UInt8], atRadius radius: Double) -> Int {
            var total = 0
            for step in 0..<720 {
                let angle = Double(step) / 720 * 2 * .pi
                let x = Int((Double(width) / 2 + cos(angle) * radius).rounded())
                let y = Int((Double(width) / 2 + sin(angle) * radius).rounded())
                guard x >= 0, x < width, y >= 0, y < width else { continue }
                let i = (y * width + x) * 4
                total += (0..<3).map { abs(Int(base[i + $0]) - Int(drawn[i + $0])) }.max() ?? 0
            }
            return total
        }

        let quietOnRing = deviation(from: plain, in: quiet, atRadius: radiusPixels)
        let loudOnRing = deviation(from: plain, in: loud, atRadius: radiusPixels)
        print("[veil] кольцо: обычное \(quietOnRing), выбранное \(loudOnRing)")
        XCTAssertGreaterThan(quietOnRing, 0, "кольцо обязано быть видно")
        XCTAssertGreaterThan(loudOnRing, quietOnRing,
                             "выбранное кольцо обязано гореть ярче обычного")

        // Ободок стоял ВНУТРЬ от кольца на четыре точки — то есть здесь.
        let insideRim = deviation(from: plain, in: quiet, atRadius: radiusPixels - 4)
        XCTAssertEqual(insideRim, 0, "тёмного ободка внутри кольца больше нет")
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
        lod: RevealedLayer.LOD, metresPerPoint: Double, withClouds: Bool,
        withRoad: Bool = true, side: Int = 400
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
                context: context, paths: withRoad ? [road] : [],
                corridorWidth: width, passes: passes,
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
            // Эталон — ТОТ ЖЕ кадр без дороги. Сравнивать с одним числом
            // больше нельзя: с «ночной картой» рампа глубины и облака живут в
            // прозрачности, и мгла честно гуляет по кадру (замер: 166…192).
            // «Нетронуто» значит «ровно как без коридора», и проверяется это
            // пиксель в пиксель.
            guard let clean = corridorRaster(
                lod: lod, metresPerPoint: metresPerPoint, withClouds: true, withRoad: false)
            else { return XCTFail("эталон обязан собраться (\(lod))") }
            for row in [mid - reach, mid + reach, 2, shot.side - 3] {
                for x in stride(from: 4, to: shot.side - 4, by: 17) {
                    let i = (row * shot.side + x) * 4 + 3
                    XCTAssertEqual(Int(shot.pixels[i]), Int(clean.pixels[i]), accuracy: 1,
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
            // Пороги ниже прежних ВДВОЕ, и не потому, что край стал хуже: с
            // «ночной картой» вся шкала альфы кончается на 0.70 × 255, и
            // размах на ней арифметически меньше. «Без облаков» при этом уже
            // не ноль — рампа глубины теперь тоже живёт в прозрачности и даёт
            // свои несколько уровней вдоль дороги.
            XCTAssertLessThanOrEqual(without, 8,
                                     "без облаков край прямой дороги обязан быть ровным (\(lod))")
            XCTAssertGreaterThan(withClouds, 18,
                                 "с облаками край обязан клубиться (\(lod))")
            XCTAssertGreaterThan(withClouds, without * 2,
                                 "рваность обязана быть от облаков, а не от рампы (\(lod))")
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

    // MARK: Светлая палитра

    /// Обе палитры — ОДНА кисть и одни правила, отличаются только числами.
    ///
    /// Проверяется это НЕ отрисовкой, и вот почему. Палитра статична (её
    /// читают и кисть, и облака, и подписи), а текстура облаков тонируется
    /// ею же и живёт в синглтоне. Тест, который на время переключает и то и
    /// другое, ломает СОСЕДЕЙ: у меня он уронил и «швы», и «рваный край», и
    /// бюджет постера — ровно та ловушка, про которую CLAUDE.md пишет «тест,
    /// не отпустивший фикстуру, роняет чужой класс». Пиксельное равенство
    /// растра и отката держит ночная палитра (`testWholeRasterMatchesTheTiledFallback`);
    /// глазами светлую дымку проверяют кадры на устройстве, где под мглой
    /// есть настоящая карта, а на симуляторе её нет вовсе.
    func testBothPalettesAreTheSameRulesWithDifferentNumbers() {
        let night = FogVeilPainter.Palette.night
        let mist = FogVeilPainter.Palette.mist
        XCTAssertTrue(night.isDark)
        XCTAssertFalse(mist.isDark)

        func luminance(_ colour: UIColor) -> CGFloat {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            colour.getRed(&r, green: &g, blue: &b, alpha: &a)
            return 0.299 * r + 0.587 * g + 0.114 * b
        }
        // Светлая дымка светлее ночной мглы, а её граница — наоборот темнее:
        // и то и другое обязано читаться на своём фоне.
        XCTAssertGreaterThan(luminance(mist.bottom), luminance(night.bottom) + 0.4)
        XCTAssertLessThan(luminance(mist.border), luminance(night.border) - 0.4)
        // The paper atlas intentionally mutes unexplored roads more than
        // the night palette (HTML 0.8.1: #EEEEEC at 87%). Both still reveal
        // the underlying map; the density range brackets the nominal alpha.
        XCTAssertEqual(mist.alpha, 0.87, accuracy: 0.001)
        XCTAssertLessThan(night.alpha, 0.85)
        for palette in [night, mist] {
            XCTAssertGreaterThan(palette.alpha, 0.55)
            XCTAssertLessThan(palette.alpha, 0.95)
            XCTAssertLessThan(palette.opacityRange.upperBound, 0.95)
            XCTAssertTrue(palette.opacityRange.contains(Double(palette.alpha)))
            XCTAssertGreaterThan(palette.opacityRange.lowerBound, 0.55)
            XCTAssertEqual(palette.opacityRange.lowerBound
                + (1 - palette.opacityRange.lowerBound)
                * ((palette.opacityRange.upperBound - palette.opacityRange.lowerBound)
                   / (1 - palette.opacityRange.lowerBound)),
                palette.opacityRange.upperBound, accuracy: 1e-9)
        }
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
