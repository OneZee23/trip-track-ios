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
