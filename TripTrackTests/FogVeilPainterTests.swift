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
        let rect = FogVeilView.renderRect(visible: visible, margin: FogVeilView.margin)
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

        let width = Int(sizePoints.width.rounded())
        let height = Int(sizePoints.height.rounded())
        guard let mine = pixels(of: band.image, width: width, height: height),
              let theirs = tiledReference(rect: rect, sizePoints: sizePoints,
                                          revealed: revealed, width: width, height: height)
        else { return XCTFail("обе картинки обязаны собраться") }

        var worse = 0
        var total = 0.0
        for i in stride(from: 0, to: mine.count, by: 4) {
            for channel in 0..<3 {
                let delta = abs(Int(mine[i + channel]) - Int(theirs[i + channel]))
                total += Double(delta)
                if delta > 8 { worse += 1; break }
            }
        }
        let count = mine.count / 4
        let share = Double(worse) / Double(count)
        let mean = total / Double(count * 3)
        print(String(format: "[veil] растр против тайлов: расходятся %.3f %% пикселей, "
                     + "средняя разница %.3f уровня", share * 100, mean))
        XCTAssertLessThan(share, 0.02,
                          "растр и плиточный откат обязаны рисовать одно и то же")
        XCTAssertLessThan(mean, 1.5, "средняя разница по каналу — меньше полутора уровней")
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
