import XCTest
import MapKit
@testable import TripTrack

/// The map's overlays are drawn tile by tile, on MapKit's own schedule, so a
/// tile that takes too long shows up as the map arriving in fragments — you
/// tap a region across the country, the camera flies there, and the new area
/// materialises one rectangle at a time.
///
/// That is not something a screenshot catches reliably (it depends on when you
/// look), so the cost is measured here instead.
final class MapRenderCostTests: XCTestCase {

    /// A small driven network around Krasnodar — one person's real shape.
    private func layer() -> RevealedLayer {
        var claimed: [String: Set<RevealGrid.Cell>] = [:]
        var runs: [[CLLocationCoordinate2D]] = []
        for pass in 0..<8 {
            let coords = (0..<120).map { i -> CLLocationCoordinate2D in
                let t = Double(i) / 119
                let phase = Double(i) * 0.6 + Double(pass) * 1.7
                return CLLocationCoordinate2D(
                    latitude: 45.00 + 0.06 * t + sin(phase) * 0.00008,
                    longitude: 38.95 + 0.09 * t + cos(phase) * 0.00008
                )
            }
            for (key, patch) in RevealBuilder.patches(for: coords, claimed: { claimed[$0] ?? [] }) {
                claimed[key, default: []].formUnion(patch.cells)
                runs.append(contentsOf: patch.runs)
            }
        }
        return RevealedLayer.build(
            runs: runs, cellCount: claimed.values.reduce(0) { $0 + $1.count }, atlas: nil)
    }

    private func context() -> CGContext {
        CGContext(
            data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }

    /// One 256-point tile at country zoom, in map points.
    private func tile(at coordinate: CLLocationCoordinate2D, span: Double) -> MKMapRect {
        let origin = MKMapPoint(coordinate)
        return MKMapRect(x: origin.x - span / 2, y: origin.y - span / 2, width: span, height: span)
    }

    private func timePerCall(_ body: () -> Void, rounds: Int = 40) -> TimeInterval {
        let started = Date()
        for _ in 0..<rounds { body() }
        return Date().timeIntervalSince(started) / Double(rounds)
    }

    /// Draws one tile the way MapKit does — with the transform that maps the
    /// renderer's own coordinates onto the tile. Without it the geometry lands
    /// far outside the context, CoreGraphics discards it for free, and every
    /// measurement here would be of nothing at all.
    private func drawTile(
        _ renderer: MKOverlayRenderer, _ mapRect: MKMapRect,
        zoom: MKZoomScale, in context: CGContext
    ) {
        let rect = renderer.rect(for: mapRect)
        context.saveGState()
        context.scaleBy(x: zoom, y: zoom)
        context.translateBy(x: -rect.origin.x, y: -rect.origin.y)
        renderer.draw(mapRect, zoomScale: zoom, in: context)
        context.restoreGState()
    }

    /// The veil covers the whole world on purpose — a corner with no veil
    /// would read as explored — so at country zoom almost every tile on screen
    /// is nowhere near a road you have driven. Those tiles are a flat fill and
    /// must not pay for the transparency layer and the stroke passes that
    /// punching corridors needs.
    func testVeilTilesWithNoRoadsAreFarCheaperThanTilesWithThem() {
        let renderer = FogVeilRenderer(veil: FogVeilOverlay(layer: layer()))
        let ctx = context()
        // Region scale: 256 pt of tile over ~48 km, where the veil is at full
        // strength and every stroke pass actually runs.
        let zoom: MKZoomScale = 0.0008
        let span = 256 / Double(zoom)

        // Over the network, and 900 km away over open steppe.
        let onNetwork = tile(at: CLLocationCoordinate2D(latitude: 45.03, longitude: 38.99),
                             span: span)
        let empty = tile(at: CLLocationCoordinate2D(latitude: 53.0, longitude: 45.0),
                         span: span)

        let busy = timePerCall { drawTile(renderer, onNetwork, zoom: zoom, in: ctx) }
        let bare = timePerCall { drawTile(renderer, empty, zoom: zoom, in: ctx) }

        print("[veil] tile with roads \(busy * 1000) ms · empty tile \(bare * 1000) ms")
        // An empty tile still has to blend 65 000 pixels of flat colour, so it
        // is never free — the win is skipping the transparency layer and the
        // stroke passes on top of that.
        XCTAssertLessThan(
            bare, busy / 2,
            "an empty tile must not cost what a corridor-punching one does — "
                + "empty \(bare * 1000) ms vs busy \(busy * 1000) ms"
        )
        // Whatever the ratio, an empty tile has to be genuinely quick: dozens
        // of them land on screen at once when the camera moves.
        XCTAssertLessThan(bare, 0.002, "empty veil tile took \(bare * 1000) ms")
    }

    /// Жилка тоже режется бакетами, поэтому тайл, в котором её нет, обязан
    /// стоить почти ничего.
    func testVeinTilesWithNoRoadsCostAlmostNothing() {
        let renderer = RouteVeinRenderer(vein: RouteVeinOverlay(layer: layer()))
        let ctx = context()
        let zoom: MKZoomScale = 0.0008
        let empty = tile(at: CLLocationCoordinate2D(latitude: 53.0, longitude: 45.0),
                         span: 256 / Double(zoom))

        let bare = timePerCall { drawTile(renderer, empty, zoom: zoom, in: ctx) }
        print("[vein] empty tile \(bare * 1000) ms")
        XCTAssertLessThan(bare, 0.001, "empty vein tile took \(bare * 1000) ms")
    }

    /// Туман непрозрачен на ВСЕХ масштабах, и первым делом на масштабе
    /// страны — именно там до 0.7.0 его не было вовсе.
    ///
    /// Решение снимать вуаль на дальнем зуме было принято сознательно («одна
    /// поздно пришедшая плитка — яркий прямоугольник размером с область»), но
    /// именно оно убивало жанр: туман войны обязан быть первым, что видишь,
    /// а человек открывает вкладку как раз на стране целиком. Вспышку это
    /// всё равно не лечило — прототип 15 сен показал, что она одинакова у
    /// полного пера и у одной заливки, то есть она не наша.
    func testVeilIsOpaqueAtEveryZoom() {
        let renderer = FogVeilRenderer(veil: FogVeilOverlay(layer: layer()))
        // Страна, регион, город, улица — везде заведомо мимо сети.
        for zoom: MKZoomScale in [3e-5, 8e-4, 4e-3, 0.06] {
            let span = 200 / Double(zoom)
            let empty = tile(at: CLLocationCoordinate2D(latitude: 53.0, longitude: 45.0), span: span)
            let alphas = Self.alphaColumn(renderer, empty, zoom: zoom)
            XCTAssertEqual(
                alphas.min() ?? 0, 255,
                "на зуме \(zoom) в тумане есть просвет — вуаль не непрозрачна")
        }
    }

    /// Тайл без дорог — это ОДНА заливка: ни слоя прозрачности, ни проходов
    /// пера. Вуаль накрывает весь мир, и этим путём идёт большинство тайлов.
    func testEmptyVeilTileIsJustAFill() {
        let renderer = FogVeilRenderer(veil: FogVeilOverlay(layer: layer()))
        let zoom: MKZoomScale = 4e-3
        let empty = tile(at: CLLocationCoordinate2D(latitude: 53.0, longitude: 45.0),
                         span: 200 / Double(zoom))
        let alphas = Set(Self.alphaColumn(renderer, empty, zoom: zoom))
        XCTAssertEqual(alphas, [255], "прочищенного в пустом тайле быть не может")
    }

    /// Альфа по вертикали через середину тайла.
    private static func alphaColumn(
        _ renderer: MKOverlayRenderer, _ mapRect: MKMapRect, zoom: MKZoomScale
    ) -> [UInt8] {
        let size = 200
        let count = size * size * 4
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        data.initialize(repeating: 0, count: count)
        defer { data.deallocate() }
        guard let ctx = CGContext(
            data: data, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }

        let rect = renderer.rect(for: mapRect)
        ctx.saveGState()
        ctx.scaleBy(x: zoom, y: zoom)
        ctx.translateBy(x: -rect.origin.x, y: -rect.origin.y)
        renderer.draw(mapRect, zoomScale: zoom, in: ctx)
        ctx.restoreGState()

        return (0..<size).map { data[($0 * size + size / 2) * 4 + 3] }
    }

    /// The selected trip's line has to be the same thickness on screen however
    /// far in or out you are. `MKGradientPolylineRenderer` rasterises once and
    /// lets MapKit rescale the result, so after a few pinches the route sat
    /// three times the width of the heat lines next to it and stayed there.
    ///
    /// This measures our replacement in pixels. It cannot reproduce MapKit's
    /// rescaling — that happens in its compositor, not in a bitmap — so it
    /// guards the contract we replaced it with, not the bug itself.
    func testSelectedRouteKeepsOneWidthAtEveryZoom() {
        let west = CLLocationCoordinate2D(latitude: 45.0, longitude: 38.80)
        let east = CLLocationCoordinate2D(latitude: 45.0, longitude: 39.20)
        guard let route = RouteVeinOverlay(route: [west, east]) else {
            return XCTFail("жилка из двух точек обязана построиться")
        }
        let renderer = RouteVeinRenderer(vein: route)
        let middle = CLLocationCoordinate2D(latitude: 45.0, longitude: 39.0)

        // Оба зума — внутри одного уровня детали: между уровнями жилка МЕНЯЕТ
        // ширину нарочно (2.2 / 2.0 / 1.6 экранных точки).
        let close = strokePixels(renderer, at: 0.004, centre: middle)
        let far = strokePixels(renderer, at: 0.002, centre: middle)

        print("[route] \(close) px close · \(far) px far")
        XCTAssertGreaterThan(close, 2, "the line has to be drawn at all")
        XCTAssertEqual(Double(close), Double(far), accuracy: 2,
                       "\(close) px close vs \(far) px far — the width is following the zoom")
    }

    /// Draws one tile and counts how many pixels the stroke covers down the
    /// middle column — the line's thickness on screen.
    private func strokePixels(
        _ renderer: MKOverlayRenderer, at zoom: MKZoomScale, centre: CLLocationCoordinate2D
    ) -> Int {
        let size = 200
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let ctx = pixels.withUnsafeMutableBytes { bytes in
            CGContext(
                data: bytes.baseAddress, width: size, height: size,
                bitsPerComponent: 8, bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }
        guard let ctx else { return 0 }

        let span = Double(size) / Double(zoom)
        let origin = MKMapPoint(centre)
        let mapRect = MKMapRect(x: origin.x - span / 2, y: origin.y - span / 2,
                                width: span, height: span)
        drawTile(renderer, mapRect, zoom: zoom, in: ctx)

        // Alpha down the centre column.
        return (0..<size).reduce(into: 0) { count, row in
            let alpha = pixels[(row * size + size / 2) * 4 + 3]
            if alpha > 40 { count += 1 }
        }
    }

    /// Region outlines are drawn from the bundled atlas, and a heavy one would
    /// show up as the border crawling in behind the camera.
    func testRegionOutlinesAreSmallEnoughToDrawAtOnce() async {
        let atlas = RegionAtlas.shared
        await atlas.loadIfNeeded()
        XCTAssertFalse(atlas.regions.isEmpty, "atlas must be bundled")

        let heaviest = atlas.regions
            .map { $0.rings.reduce(0) { $0 + $1.count / 2 } }
            .max() ?? 0
        print("[regions] heaviest outline \(heaviest) points")
        XCTAssertLessThan(heaviest, 3_000,
                          "a border this detailed cannot be filled inside one tile pass")
    }
}
