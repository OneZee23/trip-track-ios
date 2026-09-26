import XCTest
import MapKit
import Metal
@testable import TripTrack

/// Постер «Поделиться» рисует туман ТЕМ ЖЕ кодом, что экран, — и с 0.8.0 это
/// Metal.
///
/// Проверять это можно только пикселем: «постер накрыт той же мглой» не
/// выражается ни возвращаемым значением, ни состоянием. Инструмент тот же,
/// что у `AtlasSharePosterTests`, — белый «снимок»: под мглой его не видно, а
/// в прожжённом коридоре виден весь, и разница между «в коридоре» и «в
/// тумане» на нём максимальна и не зависит ни от плиток Apple, ни от сети.
///
/// Веток здесь ДВЕ, и живыми обязаны быть обе: Metal (прод) и растровый откат
/// (`isEnabledOverride = false` — то же, что Metal, недоступный на
/// устройстве). Постер, собравшийся только в одной из них, — это постер,
/// который у кого-то выйдет пустым.
final class AtlasSharePosterMetalTests: XCTestCase {

    /// Палитра мглы пришпиливается к ночной, как в `AtlasSharePosterTests`:
    /// оба пиксельных утверждения написаны про ТЁМНУЮ мглу, а на светлом
    /// симуляторе `MyMapRepresentable` выбрал бы `.mist`, и «коридор светлее
    /// тумана» падало бы там, где всё в порядке.
    private var paletteBeforeTest: FogVeilPainter.Palette?

    override func setUp() {
        super.setUp()
        paletteBeforeTest = FogVeilPainter.palette
        FogVeilPainter.palette = .night
    }

    override func tearDown() {
        // Глобалка, оставленная тестом, роняет СОСЕДЕЙ, а не его самого.
        FogMetalAvailability.isEnabledOverride = nil
        if let paletteBeforeTest { FogVeilPainter.palette = paletteBeforeTest }
        paletteBeforeTest = nil
        super.tearDown()
    }

    // MARK: Проверки

    /// Metal-туман доезжает до постера: коридор прожжён, угол закрыт мглой.
    ///
    /// Флаг взводится руками, а не берётся из прода: выключи его владелец —
    /// и тест молча проверял бы растровый откат, то есть ровно не то, ради
    /// чего написан.
    func testMetalVeilBurnsTheCorridorThroughThePoster() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal недоступен") }
        FogMetalAvailability.isEnabledOverride = true

        let (corridor, fog) = try corridorAndFogLuminance()
        print("[poster/metal] коридор \(corridor) · туман \(fog)")
        XCTAssertLessThan(fog, fogCeiling, "мгла обязана оставаться тёмной: \(fog)")
        XCTAssertGreaterThan(
            corridor, fog + 60,
            "Metal-туман не прожёг коридор: \(corridor) против мглы \(fog)")
    }

    /// Откат жив: Metal выключен — постер по-прежнему собирается, и собирает
    /// его растр 0.7.0.
    func testPosterStillComposesOnTheRasterFallback() throws {
        FogMetalAvailability.isEnabledOverride = false

        let (corridor, fog) = try corridorAndFogLuminance()
        print("[poster/raster] коридор \(corridor) · туман \(fog)")
        XCTAssertLessThan(fog, fogCeiling, "мгла обязана оставаться тёмной: \(fog)")
        XCTAssertGreaterThan(
            corridor, fog + 60,
            "растровый откат не прожёг коридор: \(corridor) против мглы \(fog)")
    }

    /// The GPU image contains fog only. The shared poster must composite the
    /// same terracotta vein that lives in a separate layer on the live Atlas.
    func testLightPosterKeepsTerracottaVeinOnMetalAndRaster() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal недоступен") }
        let savedPlus = UserDefaults.standard.bool(forKey: RouteLineStyle.plusMirrorKey)
        defer { UserDefaults.standard.set(savedPlus, forKey: RouteLineStyle.plusMirrorKey) }
        UserDefaults.standard.set(false, forKey: RouteLineStyle.plusMirrorKey)
        FogVeilPainter.palette = .mist
        let layer = straightLayer()
        let rect = try XCTUnwrap(AtlasSharePoster.frame(for: layer))
        let centre = AtlasSharePoster.project(middle, rect: rect, size: AtlasSharePoster.renderPointSize)

        for metal in [true, false] {
            FogMetalAvailability.isEnabledOverride = metal
            let poster = AtlasSharePoster.render(
                snapshot: whiteSnapshot(), region: AtlasSharePoster.region(for: rect),
                layer: layer, seals: [], caption: "", scale: 1)
            let pixels = try XCTUnwrap(raster(of: poster))
            let hasTerracotta = (-4...4).contains { dy in
                let i = ((Int(centre.y) + dy) * pixels.width + Int(centre.x)) * 4
                let red = pixels.data[i + 2], green = pixels.data[i + 1], blue = pixels.data[i]
                return red >= 190 && red <= 220 && green < 110 && blue < 90
            }
            XCTAssertTrue(hasTerracotta, "\(metal ? "Metal" : "Raster") poster lost the terracotta route")
        }
    }

    /// Кадр Metal ложится в постер ТОЙ ЖЕ стороной вверх, что растр.
    ///
    /// Дорога через середину не поймала бы переворот: она симметрична. Поэтому
    /// окно сдвигается на юг — дорога уходит в ВЕРХНЮЮ четверть картинки, и
    /// перевёрнутый кадр вынес бы её в нижнюю. Ошибка это ровно того рода, что
    /// не выражается ни значением, ни состоянием, — её видно только глазами на
    /// готовой картинке, если кто-то посмотрит.
    func testMetalVeilLandsTheRightWayUp() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal недоступен") }
        FogMetalAvailability.isEnabledOverride = true

        let layer = straightLayer()
        let fitted = try XCTUnwrap(AtlasSharePoster.frame(for: layer), "окно обязано посчитаться")
        // Y карты растёт на ЮГ: окно, сдвинутое вниз по Y, поднимает дорогу.
        let rect = MKMapRect(x: fitted.minX, y: fitted.minY + fitted.height * 0.25,
                             width: fitted.width, height: fitted.height)
        let poster = AtlasSharePoster.render(
            snapshot: whiteSnapshot(), region: AtlasSharePoster.region(for: rect),
            layer: layer, seals: [], caption: "", scale: 1)
        let raster = try XCTUnwrap(self.raster(of: poster), "пиксели обязаны читаться")

        // Куда дорогу проецирует САМА карта — с ним и сверяется картинка.
        // Проверка «в верхней половине» была бы пустой: дорога через середину
        // задевает обе, и переворот не поймался бы.
        let expected = AtlasSharePoster.project(
            middle, rect: rect, size: AtlasSharePoster.renderPointSize).y
        XCTAssertLessThan(
            expected, AtlasSharePoster.renderPointSize.height * 0.4,
            "сдвиг окна не сработал, проверять нечего")

        // Ищется ДО плашки подписи: её рампа сама светлее мглы.
        let x = Int(AtlasSharePoster.renderPointSize.width / 2)
        let strip = raster.height - Int(AtlasSharePoster.captionHeight)
        var brightest = 0.0
        var row = 0
        for y in 0..<strip where raster.luminance(x: x, y: y) > brightest {
            brightest = raster.luminance(x: x, y: y)
            row = y
        }

        print("[poster/metal] коридор в строке \(row), ждали \(expected)")
        XCTAssertEqual(Double(row), Double(expected), accuracy: 24,
                       "кадр Metal встал не на своё место (переворот?)")
    }

    // MARK: Мера

    /// Потолок яркости мглы считается ПО КОМПОЗИЦИИ, а не вписывается числом:
    /// мгла полупрозрачна («ночная карта»), и сквозь неё светит белый холст
    /// теста. Тон мглы подняли в «Атлас как атлас», и вписанное число упало бы,
    /// ничего не объяснив (то же соображение, что в `AtlasSharePosterTests`).
    private var fogCeiling: Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        FogVeilPainter.veilColorBottom.getRed(&r, green: &g, blue: &b, alpha: &a)
        let veil = (0.299 * r + 0.587 * g + 0.114 * b) * 255
        let alpha = FogVeilPainter.veilAlpha
        return veil * alpha + 255 * (1 - alpha) + 12
    }

    /// Самый светлый пиксель поперёк дороги — и пиксель заведомо мимо неё.
    ///
    /// Поперёк, а не в одну точку: коридор ≈ сотня метров, то есть больше
    /// десятка точек на этом масштабе, и попасть ровно в осевую пикселем
    /// нельзя. Мгла берётся четвертью высоты выше дороги — там не бывает ни
    /// коридора, ни нижней плашки с подписью.
    private func corridorAndFogLuminance() throws -> (corridor: Double, fog: Double) {
        let layer = straightLayer()
        let rect = try XCTUnwrap(AtlasSharePoster.frame(for: layer), "окно обязано посчитаться")
        let poster = AtlasSharePoster.render(
            snapshot: whiteSnapshot(), region: AtlasSharePoster.region(for: rect),
            layer: layer, seals: [], caption: "Атлас", scale: 1)
        XCTAssertEqual(poster.size, AtlasSharePoster.renderPointSize)

        let raster = try XCTUnwrap(self.raster(of: poster), "пиксели обязаны читаться")
        let centre = AtlasSharePoster.project(
            middle, rect: rect, size: AtlasSharePoster.renderPointSize)
        var corridor = 0.0
        for dy in -8...8 {
            corridor = max(corridor, raster.luminance(x: Int(centre.x), y: Int(centre.y) + dy))
        }
        return (corridor, raster.luminance(x: Int(centre.x), y: Int(centre.y) - 220))
    }

    // MARK: Данные

    /// Одна прямая дорога вдоль параллели — в картинке это горизонтальная
    /// линия через середину, поперёк которой удобно читать пиксели (та же
    /// форма, что у `AtlasSharePosterTests`).
    private let west = CLLocationCoordinate2D(latitude: 45.04, longitude: 38.90)
    private let east = CLLocationCoordinate2D(latitude: 45.04, longitude: 38.94)

    private var middle: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (west.latitude + east.latitude) / 2,
            longitude: (west.longitude + east.longitude) / 2)
    }

    private func straightLayer() -> RevealedLayer {
        let run = (0..<120).map { i -> CLLocationCoordinate2D in
            let t = Double(i) / 119
            return CLLocationCoordinate2D(
                latitude: west.latitude + (east.latitude - west.latitude) * t,
                longitude: west.longitude + (east.longitude - west.longitude) * t)
        }
        return RevealedLayer.build(runs: [run], cellCount: run.count, atlas: nil)
    }

    /// Белый холст ровно того размера, которым снимается карта.
    private func whiteSnapshot() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(
            size: AtlasSharePoster.renderPointSize, format: format
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: AtlasSharePoster.renderPointSize))
        }
    }

    // MARK: Чтение пикселей

    /// BGRA — тот же порядок байт, что у `FogVeilPainterTests`.
    private struct Raster {
        let data: [UInt8]
        let width: Int
        let height: Int

        func luminance(x: Int, y: Int) -> Double {
            guard x >= 0, y >= 0, x < width, y < height else { return 0 }
            let i = (y * width + x) * 4
            return 0.299 * Double(data[i + 2]) + 0.587 * Double(data[i + 1])
                + 0.114 * Double(data[i])
        }
    }

    private func raster(of image: UIImage) -> Raster? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let ok: Bool = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? Raster(data: data, width: width, height: height) : nil
    }
}
