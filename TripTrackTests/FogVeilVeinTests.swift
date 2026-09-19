import XCTest
import MapKit
@testable import TripTrack

/// «Линии пиксельные, надо сгладить, сделать серьёзными, как у трекера» —
/// владелец на устройстве 18 сентября.
///
/// Диагноз был не в сглаживании: жилка рисовалась ВНУТРИ растра вуали, а тот
/// живёт в полутора пикселях на точку (`FogVeilView.renderScale`) и на экране
/// растягивается вдвое. Туману это безразлично — у него нет ни одной резкой
/// границы, — а линия в две точки шириной идёт от этого лесенкой в два
/// экранных пикселя на ступень. Поэтому линия уехала на свой векторный слой
/// (`FogVeilVein`, `VeinLayer`): он едет за картой тем же аффинным
/// преобразованием, что и растр, но растеризуется в экранном масштабе.
final class FogVeilVeinTests: XCTestCase {

    // MARK: Общая обстановка

    /// Прямая диагональная дорога — на ней ступеньки видны лучше всего.
    private func diagonal(points: Int = 200) -> RevealedLayer {
        let run = (0..<points).map { i -> CLLocationCoordinate2D in
            let t = Double(i) / Double(points - 1)
            return CLLocationCoordinate2D(latitude: 45.000 + 0.010 * t,
                                          longitude: 38.950 + 0.014 * t)
        }
        return RevealedLayer.build(runs: [run], cellCount: points, atlas: nil)
    }

    private func index(for revealed: RevealedLayer) -> MapPathIndex {
        let index = MapPathIndex()
        index.prepare(source: { revealed.polylines(for: $0) },
                      transform: { CGPoint(x: $0.x, y: $0.y) })
        return index
    }

    /// Кадр «улица»: 440 pt видимого на 1.5 км, запас 1.5×.
    private func frame(metres: Double = 1_500) -> (rect: MKMapRect, sizePoints: CGSize) {
        let centre = CLLocationCoordinate2D(latitude: 45.005, longitude: 38.957)
        let metre = MKMapPointsPerMeterAtLatitude(centre.latitude)
        let visibleWidth = metres * metre
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

    private func pixels(of image: CGImage) -> [UInt8]? {
        let width = image.width, height = image.height
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

    // MARK: Проходы пера

    /// Сеть даёт сердцевину, выбранный маршрут — обводку и себя. Ширины берутся
    /// у `RouteVeinRenderer`, то есть у того же источника, что у плиточного
    /// отката: разъехаться этим двум нельзя.
    func testStrokesCarryTheSameWidthsAsTheTiledRenderer() {
        let revealed = diagonal()
        let (rect, sizePoints) = frame()
        let zoomScale = MKZoomScale(sizePoints.width / CGFloat(rect.width))
        let lod = FogVeilRenderer.lod(for: zoomScale)
        let chunks = index(for: revealed).ready(for: lod)

        let net = FogVeilVein.strokes(rect: rect, sizePoints: sizePoints,
                                      chunks: chunks, selected: [])
        XCTAssertFalse(net.isEmpty, "сеть обязана дать хотя бы сердцевину")
        XCTAssertEqual(net.last?.width ?? 0, RouteVeinRenderer.width(for: lod), accuracy: 0.01)

        let route = [MKMapPoint(x: rect.midX, y: rect.midY),
                     MKMapPoint(x: rect.midX + rect.width / 4, y: rect.midY + rect.height / 4)]
        let both = FogVeilVein.strokes(rect: rect, sizePoints: sizePoints,
                                       chunks: chunks, selected: route)
        XCTAssertEqual(both.count, net.count + 2, "у выбранного маршрута обводка и сам он")
        XCTAssertEqual(both[both.count - 2].width,
                       RouteVeinRenderer.selectedWidth + RouteVeinRenderer.casingExtra,
                       accuracy: 0.01)
        XCTAssertEqual(both.last?.width ?? 0, RouteVeinRenderer.selectedWidth, accuracy: 0.01)
    }

    /// Пути приезжают в координатах РАСТРА: левый верхний угол — ноль, единица
    /// измерения — точка экрана.
    func testPathsArriveInRasterPointSpace() {
        let (rect, sizePoints) = frame()
        let route = [MKMapPoint(x: rect.minX, y: rect.minY),
                     MKMapPoint(x: rect.maxX, y: rect.maxY)]
        guard let stroke = FogVeilVein.strokes(
            rect: rect, sizePoints: sizePoints, chunks: nil, selected: route).last
        else { return XCTFail("выбранный маршрут обязан дать проход") }
        let box = stroke.path.boundingBox
        XCTAssertEqual(box.minX, 0, accuracy: 0.5)
        XCTAssertEqual(box.minY, 0, accuracy: 0.5)
        XCTAssertEqual(box.maxX, sizePoints.width, accuracy: 0.5)
        XCTAssertEqual(box.maxY, sizePoints.height, accuracy: 0.5)
    }

    // MARK: Сглаживание

    /// Край жилки СГЛАЖЕН: поперёк диагонали есть пиксели промежуточной
    /// яркости, а не только «туман» и «жилка».
    ///
    /// Меряется на растре с жилкой против растра без неё: так не нужно знать,
    /// где именно прошла дорога, а «есть ли полутон» спрашивается ровно у тех
    /// пикселей, которые жилка и изменила. Это тот же путь, которым рисует
    /// постер и плиточный откат, — если сглаживание выключат там, тест упадёт.
    func testVeinEdgeIsAntialiased() throws {
        let revealed = diagonal()
        let (rect, sizePoints) = frame()
        let index = index(for: revealed)
        guard let bare = FogVeilBitmap.render(
                  rect: rect, sizePoints: sizePoints, scale: 1,
                  index: index, selected: [], vein: false),
              let veined = FogVeilBitmap.render(
                  rect: rect, sizePoints: sizePoints, scale: 1,
                  index: index, selected: [], vein: true)
        else { return XCTFail("оба растра обязаны собраться") }
        let a = try XCTUnwrap(pixels(of: bare.image))
        let b = try XCTUnwrap(pixels(of: veined.image))
        XCTAssertEqual(a.count, b.count)

        var peak = 0
        var deltas: [Int] = []
        for i in stride(from: 0, to: a.count, by: 4) {
            let d = max(abs(Int(a[i + 1]) - Int(b[i + 1])),
                        abs(Int(a[i + 2]) - Int(b[i + 2])),
                        abs(Int(a[i + 3]) - Int(b[i + 3])))
            if d > 0 { deltas.append(d); peak = max(peak, d) }
        }
        XCTAssertGreaterThan(peak, 20, "жилка обязана быть видна на растре")
        let partial = deltas.filter { Double($0) / Double(peak) > 0.15
                                      && Double($0) / Double(peak) < 0.6 }
        var hist = [Int](repeating: 0, count: 10)
        for d in deltas { hist[min(9, d * 10 / max(1, peak))] += 1 }
        print("[vein] изменённых пикселей \(deltas.count), полутоновых \(partial.count),"
              + " пик \(peak), гистограмма \(hist)")
        XCTAssertGreaterThan(
            partial.count, deltas.count / 20,
            "край жилки — ступенька, а не сглаженная линия")
    }

    /// Вуаль жилку в растр НЕ пишет: она живёт слоем. Постер и тесты — пишут:
    /// им отдать слой некуда.
    func testVeilRasterLeavesTheVeinToItsLayer() throws {
        let revealed = diagonal()
        let (rect, sizePoints) = frame()
        let index = index(for: revealed)
        guard let bare = FogVeilBitmap.render(
                  rect: rect, sizePoints: sizePoints, scale: 1,
                  index: index, selected: [], vein: false),
              let poster = FogVeilBitmap.render(
                  rect: rect, sizePoints: sizePoints, scale: 1,
                  index: index, selected: [])
        else { return XCTFail("оба растра обязаны собраться") }
        let a = try XCTUnwrap(pixels(of: bare.image))
        let b = try XCTUnwrap(pixels(of: poster.image))
        XCTAssertNotEqual(a, b, "по умолчанию жилка обязана оставаться в растре — это постер")
    }

    // MARK: Цена

    /// Сборка путей на зрелой библиотеке укладывается в 15 мс: она идёт один
    /// раз на растр, а не на кадр жеста, но кадр после неё обязан лечь сразу.
    func testPathRebuildFitsTheBudgetOnAMatureLibrary() {
        var runs: [[CLLocationCoordinate2D]] = []
        for line in 0..<1_000 {
            let lat = 44.9 + Double(line % 40) * 0.004
            let lon = 38.85 + Double(line / 40) * 0.006
            runs.append((0..<40).map { i in
                CLLocationCoordinate2D(latitude: lat + Double(i) * 0.0001,
                                       longitude: lon + Double(i) * 0.00014)
            })
        }
        let revealed = RevealedLayer.build(runs: runs, cellCount: runs.count * 40, atlas: nil)
        let (rect, sizePoints) = frame(metres: 6_000)
        let built = index(for: revealed)
        let zoomScale = MKZoomScale(sizePoints.width / CGFloat(rect.width))
        let chunks = built.ready(for: FogVeilRenderer.lod(for: zoomScale))
        // Прогрев: бюджетный тест обязан мерить проход, а не холодный старт.
        _ = FogVeilVein.strokes(rect: rect, sizePoints: sizePoints,
                                chunks: chunks, selected: [])

        let started = CACurrentMediaTime()
        let strokes = FogVeilVein.strokes(rect: rect, sizePoints: sizePoints,
                                          chunks: chunks, selected: [])
        let cost = CACurrentMediaTime() - started
        print(String(format: "[vein] сборка путей %.1f мс, проходов %d", cost * 1000,
                     strokes.count))
        XCTAssertFalse(strokes.isEmpty, "мерить нечего: путей должно быть много")
        XCTAssertLessThan(cost, 0.015, "сборка путей жилки перестала укладываться в кадр")
    }

    // MARK: Слой

    /// Слой растеризуется в ЭКРАННОМ масштабе — ради этого всё и делалось.
    @MainActor
    func testVeinLayerRasterisesAtScreenScale() {
        XCTAssertEqual(FogVeilView.veinScale, UIScreen.main.scale)
        let revealed = diagonal()
        let (rect, sizePoints) = frame()
        let zoomScale = MKZoomScale(sizePoints.width / CGFloat(rect.width))
        let chunks = index(for: revealed).ready(for: FogVeilRenderer.lod(for: zoomScale))
        let strokes = FogVeilVein.strokes(rect: rect, sizePoints: sizePoints,
                                          chunks: chunks, selected: [])
        let layer = VeinLayer()
        layer.apply(strokes, bounds: CGRect(origin: .zero, size: sizePoints),
                    scale: FogVeilView.veinScale)
        XCTAssertEqual(layer.strokeCount, strokes.count)
        XCTAssertGreaterThan(FogVeilView.veinScale, FogVeilView.renderScale,
                             "слой обязан быть чётче растра — иначе выносить его незачем")
        for shape in layer.sublayers ?? [] where !shape.isHidden {
            XCTAssertEqual(shape.contentsScale, UIScreen.main.scale)
        }
    }

    /// Слои переиспользуются: пустой набор гасит их, а не плодит новые.
    @MainActor
    func testLayerReusesItsShapesInsteadOfGrowing() {
        let layer = VeinLayer()
        let box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 100, y: 100))
        let stroke = FogVeilVein.Stroke(path: path, width: 2, color: .orange)
        layer.apply([stroke, stroke, stroke], bounds: box, scale: 3)
        XCTAssertEqual(layer.sublayers?.count, 3)
        XCTAssertEqual(layer.strokeCount, 3)
        layer.apply([stroke], bounds: box, scale: 3)
        XCTAssertEqual(layer.sublayers?.count, 3, "слои переиспользуются, а не пересоздаются")
        XCTAssertEqual(layer.strokeCount, 1)
        layer.apply([], bounds: box, scale: 3)
        XCTAssertEqual(layer.strokeCount, 0)
    }

    /// Жилка лежит ВЫШЕ полос растра, в каком бы порядке те ни легли: полосы
    /// приезжают по одной и каждая вставляется сверху.
    @MainActor
    func testVeinSitsAboveTheRasterBands() {
        XCTAssertGreaterThan(VeinLayer().zPosition, 0)
    }
}
