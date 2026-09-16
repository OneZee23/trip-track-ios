import XCTest
import MapKit
@testable import TripTrack

/// Экранная вуаль держится на трёх утверждениях, и каждое из них — чистая
/// функция, потому что проверить их на живой карте нельзя: «коридор уехал от
/// дороги» и «туман перерисовывается на каждый кадр» видны только числом.
final class FogVeilViewTests: XCTestCase {

    // MARK: Прямоугольник растра

    /// Запас 1.5× — вокруг видимой области, а не с одной стороны.
    func testRenderRectGrowsAroundTheVisibleArea() {
        let visible = MKMapRect(x: 1_000_000, y: 2_000_000, width: 100_000, height: 200_000)
        let rect = FogVeilView.renderRect(visible: visible, margin: 1.5)

        XCTAssertEqual(rect.width, visible.width * 1.5, accuracy: 1)
        XCTAssertEqual(rect.height, visible.height * 1.5, accuracy: 1)
        XCTAssertEqual(rect.midX, visible.midX, accuracy: 1, "запас обязан лечь вокруг центра")
        XCTAssertEqual(rect.midY, visible.midY, accuracy: 1)
        XCTAssertTrue(rect.contains(visible.origin))
    }

    /// Мир не бесконечен: у полюсов и за 180-м меридианом растр обрезается, а
    /// не уезжает в координаты, которых нет.
    func testRenderRectIsClampedToTheWorld() {
        let world = MKMapRect.world
        let visible = MKMapRect(x: 0, y: 0, width: world.width, height: world.height)
        let rect = FogVeilView.renderRect(visible: visible, margin: 1.5)

        XCTAssertGreaterThanOrEqual(rect.minX, world.minX)
        XCTAssertGreaterThanOrEqual(rect.minY, world.minY)
        XCTAssertLessThanOrEqual(rect.maxX, world.maxX)
        XCTAssertLessThanOrEqual(rect.maxY, world.maxY)
    }

    /// Запас 1 — это сам видимый прямоугольник: так считается `needed`, по
    /// которому решается устаревание.
    func testRenderRectWithNoMarginIsTheVisibleRect() {
        let visible = MKMapRect(x: 10, y: 20, width: 300, height: 400)
        let rect = FogVeilView.renderRect(visible: visible, margin: 1)
        XCTAssertEqual(rect.minX, visible.minX, accuracy: 0.001)
        XCTAssertEqual(rect.width, visible.width, accuracy: 0.001)
    }

    // MARK: Устаревание

    func testRasterIsStaleOnlyWhenItRunsOutOrGoesSoft() {
        let raster = MKMapRect(x: 0, y: 0, width: 1_500, height: 1_500)
        let inside = MKMapRect(x: 400, y: 400, width: 1_000, height: 1_000)

        XCTAssertFalse(
            VeilRenderGate.isStale(raster: raster, needed: inside, ratio: 2, margin: 1.5),
            "видимое внутри растра и масштаб тот же — перерисовывать нечего")

        let shifted = MKMapRect(x: 900, y: 400, width: 1_000, height: 1_000)
        XCTAssertTrue(
            VeilRenderGate.isStale(raster: raster, needed: shifted, ratio: 2, margin: 1.5),
            "видимое вылезло за край растра")

        // Щипок внутрь: растр стал мылом — 1500 / 300 = 5 против потолка 3.
        let zoomedIn = MKMapRect(x: 600, y: 600, width: 300, height: 300)
        XCTAssertTrue(
            VeilRenderGate.isStale(raster: raster, needed: zoomedIn, ratio: 2, margin: 1.5))
        // Тот же щипок ВО ВРЕМЯ жеста (проверка растяжения выключена) —
        // перерисовки не заказывает.
        XCTAssertFalse(
            VeilRenderGate.isStale(raster: raster, needed: zoomedIn,
                                   ratio: .greatestFiniteMagnitude, margin: 1.5))
    }

    // MARK: Матрица из трёх точек

    /// Без наклона проекция «мир → экран» — перенос, масштаб и поворот: три
    /// точки задают её ТОЧНО, и четвёртый угол ложится ровно туда, куда
    /// сказала матрица.
    func testAffineFrameHasZeroResidualWithoutPitch() {
        let size = CGSize(width: 660, height: 1_434)
        // Поворот на 30°, масштаб 0.7, сдвиг — всё, что карта делает без
        // наклона.
        let angle = CGFloat.pi / 6
        let scale: CGFloat = 0.7
        func project(_ p: CGPoint) -> CGPoint {
            CGPoint(
                x: 120 + scale * (p.x * cos(angle) - p.y * sin(angle)),
                y: -40 + scale * (p.x * sin(angle) + p.y * cos(angle))
            )
        }
        let frame = VeilFrame(
            p00: project(.zero),
            p10: project(CGPoint(x: size.width, y: 0)),
            p01: project(CGPoint(x: 0, y: size.height)),
            size: size
        )
        guard let frame else { return XCTFail("матрица из трёх точек обязана собраться") }

        let corner = frame.residual(
            measured: project(CGPoint(x: size.width, y: size.height)), atX: 1, y: 1)
        let centre = frame.residual(
            measured: project(CGPoint(x: size.width / 2, y: size.height / 2)), atX: 0.5, y: 0.5)
        XCTAssertEqual(corner, 0, accuracy: 0.001, "невязка в углу обязана быть нулём")
        XCTAssertEqual(centre, 0, accuracy: 0.001, "невязка в центре обязана быть нулём")
    }

    /// С наклоном появляется перспектива, и аффинная матрица её не выражает.
    /// Тест стоит ровно за этим: включат `isPitchEnabled` — упадёт он, а не
    /// поездка.
    func testAffineFrameResidualGrowsWithPitch() {
        let size = CGSize(width: 660, height: 1_434)
        // Деление на (1 + k·y) — это и есть перспектива: чем дальше от
        // наблюдателя, тем сильнее сжатие.
        func project(_ p: CGPoint) -> CGPoint {
            let w = 1 + 0.0004 * p.y
            return CGPoint(x: 200 + p.x / w, y: 100 + p.y / w)
        }
        let frame = VeilFrame(
            p00: project(.zero),
            p10: project(CGPoint(x: size.width, y: 0)),
            p01: project(CGPoint(x: 0, y: size.height)),
            size: size
        )
        guard let frame else { return XCTFail("матрица из трёх точек обязана собраться") }

        let corner = frame.residual(
            measured: project(CGPoint(x: size.width, y: size.height)), atX: 1, y: 1)
        XCTAssertGreaterThan(corner, 1,
                             "при наклоне коридор обязан уехать от дороги — иначе сторожа нет")
    }

    func testAffineFrameRefusesADegenerateRaster() {
        XCTAssertNil(VeilFrame(p00: .zero, p10: .zero, p01: .zero, size: .zero))
        XCTAssertNil(VeilFrame(p00: CGPoint(x: CGFloat.nan, y: 0), p10: .zero, p01: .zero,
                               size: CGSize(width: 10, height: 10)))
    }

    // MARK: Полосы

    /// Полосы режутся целым числом РЯДОВ тайлов и покрывают растр без щелей и
    /// без нахлёста: половина тайла в полосе получила бы свой градиент
    /// глубины, то есть шов посреди тумана.
    func testBandsSplitTheRasterByWholeTileRows() {
        let rect = MKMapRect(x: 1_000, y: 2_000, width: 900, height: 1_200)
        let grid = FogVeilBitmap.grid(sizePoints: CGSize(width: 660, height: 1_434))
        let bands = FogVeilBitmap.bandRects(rect: rect, grid: grid, bands: 3)

        XCTAssertEqual(bands.count, 3)
        XCTAssertEqual(bands[0].minY, rect.minY, accuracy: 0.001)
        XCTAssertEqual(bands[2].maxY, rect.maxY, accuracy: 0.001)
        for band in bands {
            XCTAssertEqual(band.minX, rect.minX, accuracy: 0.001, "полосы идут во всю ширину")
            XCTAssertEqual(band.width, rect.width, accuracy: 0.001)
        }
        for (a, b) in zip(bands, bands.dropFirst()) {
            XCTAssertEqual(a.maxY, b.minY, accuracy: 0.001, "между полосами не должно быть щели")
        }
        let tileH = rect.height / Double(grid.rows)
        for band in bands {
            let rows = band.height / tileH
            XCTAssertEqual(rows, rows.rounded(), accuracy: 0.001,
                           "полоса обязана быть целым числом рядов тайлов")
        }
    }

    /// Растр в один ряд тайлов на три полосы не режется: полос столько,
    /// сколько рядов.
    func testBandsNeverOutnumberTileRows() {
        let rect = MKMapRect(x: 0, y: 0, width: 100, height: 100)
        let grid = FogVeilBitmap.grid(sizePoints: CGSize(width: 200, height: 200))
        XCTAssertEqual(grid.rows, 1)
        XCTAssertEqual(FogVeilBitmap.bandRects(rect: rect, grid: grid, bands: 3).count, 1)
    }

    // MARK: Полосы и подмена растра

    /// ВО ВРЕМЯ ЖЕСТА растр всегда один, сколько бы он ни стоил.
    ///
    /// Гейт и так пускает сюда только исчерпание растра (видимое вылезло за
    /// край), но приезжать эта картинка обязана ЦЕЛИКОМ: три полосы ложатся на
    /// экран в разные кадры движущейся карты, и это ровно те «подгружаемые
    /// квадратики по краям», которые владелец увидел 16 сен.
    func testAGestureNeverSplitsTheRasterIntoBands() {
        XCTAssertEqual(FogVeilView.bandCount(settled: false, fullFrameCost: nil), 1)
        XCTAssertEqual(FogVeilView.bandCount(settled: false, fullFrameCost: 0.4), 1,
                       "даже на медленном устройстве жест получает один растр")
    }

    /// В покое полосы включает ЗАМЕР, а не вера.
    ///
    /// Пока полный кадр дешевле `bandThreshold`, три картинки в разные кадры
    /// только вредят; дороже — лучше показать треть вовремя, чем всё с
    /// опозданием.
    func testBandsAtRestOnlyOnASlowDevice() {
        XCTAssertEqual(FogVeilView.bandCount(settled: true, fullFrameCost: nil), 1,
                       "до замера устройство считается быстрым")
        XCTAssertEqual(FogVeilView.bandCount(settled: true, fullFrameCost: 0.05), 1)
        XCTAssertEqual(FogVeilView.bandCount(settled: true, fullFrameCost: 0.2),
                       FogVeilView.bands)
        XCTAssertEqual(FogVeilView.bandCount(settled: true,
                                             fullFrameCost: FogVeilView.bandThreshold), 1,
                       "ровно на пороге ещё быстро")
    }

    /// Запас «Атласа» — два, и это не то же число, что у карты-героя.
    ///
    /// Полтора переживали щипок ровно до полутора экранов, а дальше край
    /// растра выезжал на экран прямым швом между туманом с коридорами и ровным
    /// туманом без них. Карта записи и полноэкранная карта поездки при этом
    /// остаются на 2.2: их ещё и вращают.
    func testAtlasAsksForAWiderRasterThanTheHeroMap() {
        XCTAssertEqual(FogVeilView.atlasMargin, 2.0, accuracy: 0.0001)
        XCTAssertGreaterThan(FogVeilView.atlasMargin, FogVeilView.defaultMargin)
        XCTAssertEqual(FogVeilView.rotatingMargin, 2.2, accuracy: 0.0001,
                       "запас вращаемой карты правится только прототипом")

        // Цена запаса — площадь, и она растёт квадратом: 2.0² / 1.5² = 1.78.
        let visible = MKMapRect(x: 1_000_000, y: 2_000_000, width: 100_000, height: 200_000)
        let atlas = FogVeilView.renderRect(visible: visible, margin: FogVeilView.atlasMargin)
        let hero = FogVeilView.renderRect(visible: visible, margin: FogVeilView.defaultMargin)
        let growth = (atlas.width * atlas.height) / (hero.width * hero.height)
        XCTAssertEqual(growth, 1.78, accuracy: 0.01)
    }

    // MARK: Гейт перерисовки

    /// Жест даёт шестьдесят колбэков в секунду. Кадров тумана за ту же секунду
    /// обязано быть единицы: полный кадр `.fine` стоит десятки миллисекунд, и
    /// перерисовка на каждый колбэк забивает фоновую очередь — карта начинает
    /// дёргаться ровно там, где человек возит пальцем.
    func testAGestureDoesNotRedrawFrameByFrame() {
        var gate = VeilRenderGate()
        gate.raster = MKMapRect(x: 0, y: 0, width: 1_500, height: 1_500)
        var now: TimeInterval = 100

        // Щипок наружу: видимое каждый кадр вылезает за край растра, то есть
        // «устарело» всегда — ограничивает только расписание.
        for step in 0..<60 {
            now += 1.0 / 60
            let needed = MKMapRect(x: 1_400 + Double(step), y: 0, width: 1_000, height: 1_000)
            _ = gate.allows(now: now, needed: needed, settled: false, margin: 1.5)
        }

        XCTAssertLessThanOrEqual(gate.renders, 6,
                                 "за секунду жеста заказано \(gate.renders) кадров")
        XCTAssertGreaterThan(gate.renders, 0, "совсем не рисовать тоже нельзя")
    }

    /// Камера встала — чёткий кадр заказывается, даже если видимое всё ещё
    /// внутри растра: масштаб ушёл, и растянутый растр пора заменить.
    func testSettledCameraAsksForACrispFrame() {
        var gate = VeilRenderGate()
        gate.raster = MKMapRect(x: 0, y: 0, width: 1_500, height: 1_500)
        let zoomedIn = MKMapRect(x: 600, y: 600, width: 300, height: 300)

        XCTAssertFalse(gate.allows(now: 100, needed: zoomedIn, settled: false, margin: 1.5),
                       "во время жеста растянутый растр перерисовывать нельзя")
        XCTAssertTrue(gate.allows(now: 101, needed: zoomedIn, settled: true, margin: 1.5))
    }

    /// Смена данных бьёт и расписание, и растр: открытый мир изменился, и
    /// ждать двести миллисекунд с прежней картинкой не за чем.
    func testInvalidateLetsTheNextFrameThroughAtOnce() {
        var gate = VeilRenderGate()
        gate.raster = MKMapRect(x: 0, y: 0, width: 1_500, height: 1_500)
        let needed = MKMapRect(x: 1_400, y: 0, width: 1_000, height: 1_000)
        XCTAssertTrue(gate.allows(now: 100, needed: needed, settled: true, margin: 1.5))
        XCTAssertFalse(gate.allows(now: 100.05, needed: needed, settled: true, margin: 1.5))

        gate.invalidate()
        XCTAssertTrue(gate.allows(now: 100.06, needed: needed, settled: true, margin: 1.5))
    }

    // MARK: Летербокс — «сырая карта не видна никогда»

    /// Четыре угла прямоугольника — тот же четырёхугольник, только без
    /// поворота: им проверяются случаи, где поворота нет.
    private func quad(_ rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }

    /// Четырёхугольник, повёрнутый на угол вокруг своего центра, — так растр
    /// лежит на экране записи в режиме «по курсу».
    private func rotatedQuad(_ rect: CGRect, by angle: CGFloat) -> [CGPoint] {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        return quad(rect).map { point in
            let dx = point.x - centre.x, dy = point.y - centre.y
            return CGPoint(x: centre.x + dx * cos(angle) - dy * sin(angle),
                           y: centre.y + dx * sin(angle) + dy * cos(angle))
        }
    }

    /// Дополнение считается по последнему ПОЛНОМУ растру.
    ///
    /// Заказанный, но ещё пустой растр накрывает экран по построению (запас
    /// 1.5×). Посчитать дополнение по нему — значит объявить непрозрачным то,
    /// чего ещё нет: кольцо вокруг старого растра станет прозрачным на все
    /// 20–120 мс отрисовки, а на ПЕРВОМ кадре «Атласа» прозрачным будет весь
    /// экран. Плиточные оверлеи к этому моменту уже сняты — там голая карта
    /// Apple.
    func testCoveredQuadIgnoresTheRasterStillBeingDrawn() {
        let old = quad(CGRect(x: 60, y: 140, width: 200, height: 400))
        let incoming = quad(CGRect(x: -100, y: -200, width: 600, height: 1_300))

        XCTAssertEqual(
            FogVeilView.coveredQuad(rasters: [(old, true), (incoming, false)]), old,
            "пока новый растр пуст, непрозрачен только старый")
        XCTAssertEqual(
            FogVeilView.coveredQuad(rasters: [(old, true), (incoming, true)]), incoming,
            "новый растр дорисован — дополнение считается по нему")
        XCTAssertEqual(
            FogVeilView.coveredQuad(rasters: [(incoming, false)]), [],
            "первый кадр: накрыто НИЧЕГО, и ровный туман обязан закрыть весь экран")
        XCTAssertEqual(
            FogVeilView.coveredQuad(rasters: [([CGPoint.zero, .zero], true)]), [],
            "растр без привязки к экрану не накрывает ничего")
    }

    /// Ни одной прозрачной точки на экране — ни при каком положении растра,
    /// включая «растра ещё нет», «растр мельче экрана» и ПОВЁРНУТЫЙ растр.
    func testFlatVeilLeavesNoTransparentPointOnScreen() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let cases: [(String, [CGPoint])] = [
            ("растра ещё нет", []),
            ("старый растр мельче экрана", quad(CGRect(x: 60, y: 140, width: 200, height: 400))),
            ("растр шире экрана", quad(CGRect(x: -100, y: -200, width: 600, height: 1_300))),
            ("растр уехал за край", quad(CGRect(x: -700, y: 300, width: 200, height: 200))),
            ("повёрнут на 30°",
             rotatedQuad(CGRect(x: 40, y: 120, width: 300, height: 500), by: .pi / 6)),
            ("повёрнут на 45° и мельче экрана",
             rotatedQuad(CGRect(x: 90, y: 300, width: 200, height: 200), by: .pi / 4)),
        ]
        for (name, covered) in cases {
            let path = FogVeilView.letterboxPath(bounds: bounds, quad: covered)
            let raster = CGMutablePath()
            if covered.count == 4 { raster.addLines(between: covered + [covered[0]]) }
            var holes = 0
            for x in stride(from: 0.5, to: bounds.width, by: 3.0) {
                for y in stride(from: 0.5, to: bounds.height, by: 3.0) {
                    let point = CGPoint(x: x, y: y)
                    if covered.count == 4, raster.contains(point) { continue }
                    if path.contains(point, using: CGPathFillRule.evenOdd) { continue }
                    holes += 1
                }
            }
            XCTAssertEqual(holes, 0, "\(name): \(holes) точек экрана прозрачны")
        }
    }

    /// Ровный туман не лезет ПОД растр — ни при каком повороте.
    ///
    /// Лез бы — и каждый прожжённый коридор светился бы изнутри собственным
    /// туманом вместо живой карты: дыра есть, а в дыре темнота.
    func testFlatVeilDoesNotCreepUnderTheRaster() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let angles: [CGFloat] = [0, .pi / 8, .pi / 4, .pi / 3]
        for angle in angles {
            let covered = rotatedQuad(CGRect(x: 40, y: 120, width: 300, height: 500), by: angle)
            let path = FogVeilView.letterboxPath(bounds: bounds, quad: covered)
            // Точки заведомо ВНУТРИ растра: центр и четыре четверти от центра.
            let centre = CGPoint(
                x: covered.reduce(CGFloat(0)) { $0 + $1.x } / 4,
                y: covered.reduce(CGFloat(0)) { $0 + $1.y } / 4)
            var inside = [centre]
            for corner in covered {
                inside.append(CGPoint(x: centre.x + (corner.x - centre.x) * 0.5,
                                      y: centre.y + (corner.y - centre.y) * 0.5))
            }
            for point in inside {
                XCTAssertFalse(path.contains(point, using: CGPathFillRule.evenOdd),
                               "ровный туман лёг под растр на повороте \(angle)")
            }
        }
    }

    /// Запас 2.2× на карте, которую вращают, — про то, что с курсом МЕНЯЕТСЯ
    /// ФОРМА видимой коробки: у повёрнутого на 45° экрана она шире по каждой
    /// стороне в 1.41 раза. Сам растр от этого за край не вылезает, а вот
    /// ЗАПАС съедается почти весь: от полутора остаётся шесть процентов, то
    /// есть полный кадр тумана на каждое движение пальцем. 2.2 оставляет те же
    /// полтора, на которых построено расписание перерисовки.
    func testRotatingMarginKeepsItsSlackThroughAQuarterTurn() {
        let visible = MKMapRect(x: 1_000_000, y: 2_000_000, width: 100_000, height: 200_000)
        // Коробка того же экрана, повёрнутого на 45°: обе стороны × √2.
        let turned = visible.insetBy(dx: -visible.width * (1.4143 - 1) / 2,
                                     dy: -visible.height * (1.4143 - 1) / 2)

        let roomy = FogVeilView.renderRect(visible: visible, margin: FogVeilView.rotatingMargin)
        XCTAssertGreaterThan(roomy.width / turned.width, 1.5,
                             "после поворота запас обязан остаться тем же, на котором стоит "
                             + "расписание перерисовки")

        let tight = FogVeilView.renderRect(visible: visible, margin: FogVeilView.defaultMargin)
        XCTAssertLessThan(tight.width / turned.width, 1.1,
                          "с запасом 1.5 после поворота остаётся шесть процентов — это кадр "
                          + "тумана на каждое движение пальцем")

        // И тот и другой растр повёрнутую коробку всё-таки НАКРЫВАЮТ: дыр в
        // тумане поворот не делает, разговор только о цене.
        XCTAssertTrue(roomy.contains(MKMapPoint(x: turned.minX, y: turned.minY)))
        XCTAssertTrue(tight.contains(MKMapPoint(x: turned.minX, y: turned.minY)))
    }

    // MARK: Встраивание и откат

    /// Имя `MKAnnotationContainerView` приватное, поэтому ищем по подстроке —
    /// и находим его на любой глубине.
    func testVeilFindsTheAnnotationContainerByClassName() {
        let root = UIView()
        let content = UIView()
        let container = AnnotationContainerStub()
        root.addSubview(content)
        content.addSubview(UIView())
        content.addSubview(container)

        XCTAssertTrue(FogVeilView.annotationContainer(in: root) === container)

        let veil = FogVeilView()
        XCTAssertTrue(veil.attach(inside: root))
        XCTAssertTrue(veil.superview === content, "вуаль обязана встать в родителя контейнера")
        let order = content.subviews
        XCTAssertLessThan(order.firstIndex(of: veil)!, order.firstIndex(of: container)!,
                          "вуаль обязана лежать ПОД аннотациями")
    }

    /// Контейнер ищется ВШИРЬ. В настоящем дереве он — прямая сабвью
    /// `_MKMapContentView`, но её сосед слева (`MKBasicMapView`) при обходе в
    /// глубину разбирается целиком раньше: любой приватный класс внутри
    /// хостинга карты с тем же словом в имени увёл бы вуаль ПОД слой Metal —
    /// молча, с `attach == true` и снятыми оверлеями, то есть без тумана.
    func testAnnotationContainerSearchIsBreadthFirst() {
        let root = UIView()
        let basicMap = UIView()
        let hosting = UIView()
        let deep = DeepAnnotationContainerStub()
        hosting.addSubview(deep)
        basicMap.addSubview(hosting)
        let container = AnnotationContainerStub()
        root.addSubview(basicMap)      // сосед слева, глубже
        root.addSubview(container)     // нужный, мельче

        XCTAssertTrue(FogVeilView.annotationContainer(in: root) === container,
                      "в глубину нашёлся бы контейнер внутри хостинга карты")
    }

    /// MapKit вправе пересобрать свои сабвью, и вуаль из дерева вылетит. Пока
    /// `screenVeilAttached == true`, плиточных оверлеев на карте нет — значит
    /// «Атлас» остался бы БЕЗ тумана вовсе, хуже, чем до 0.7.0.
    func testVeilReseatsItselfWhenMapKitRebuildsTheTree() {
        let root = UIView()
        let content = UIView()
        root.addSubview(content)
        let container = AnnotationContainerStub()
        content.addSubview(container)

        let veil = FogVeilView()
        var lost = 0
        veil.onLostFromHierarchy = { lost += 1 }
        XCTAssertTrue(veil.attach(inside: root))

        // Вылетела из дерева.
        veil.removeFromSuperview()
        veil.verifySeating()
        XCTAssertTrue(veil.superview === content, "вуаль обязана вернуться в дерево")
        XCTAssertEqual(lost, 0)

        // Оказалась ПОВЕРХ аннотаций — тоже не своё место.
        content.bringSubviewToFront(veil)
        veil.verifySeating()
        let order = content.subviews
        XCTAssertLessThan(order.firstIndex(of: veil)!, order.firstIndex(of: container)!)
        XCTAssertEqual(lost, 0)

        // Контейнера в дереве больше нет — вернуться некуда, зовущий обязан
        // поставить обратно плиточный оверлей.
        container.removeFromSuperview()
        veil.verifySeating()
        XCTAssertEqual(lost, 1, "потерю места обязаны сообщить ровно один раз")
        XCTAssertNil(veil.superview)
    }

    /// Иерархию Apple вправе переписать в любой версии. Тогда вуаль не
    /// встаёт, а туман рисует плиточный `FogVeilRenderer` — без падения и без
    /// голой карты.
    func testVeilFallsBackWhenTheContainerIsMissing() {
        let root = UIView()
        root.addSubview(UIView())
        root.subviews[0].addSubview(UIView())

        XCTAssertNil(FogVeilView.annotationContainer(in: root))
        let veil = FogVeilView()
        XCTAssertFalse(veil.attach(inside: root))
        XCTAssertNil(veil.superview, "не встроились — значит на экране нас нет вовсе")
    }
}

/// Подставной контейнер аннотаций: настоящий приватный, а поиск идёт по
/// подстроке имени класса — ровно это и проверяется.
final class AnnotationContainerStub: UIView {}

/// Такой же по имени, но ГЛУБЖЕ — им проверяется, что поиск идёт вширь.
final class DeepAnnotationContainerStub: UIView {}
