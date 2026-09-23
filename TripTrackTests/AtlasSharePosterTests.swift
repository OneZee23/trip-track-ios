import XCTest
import MapKit
@testable import TripTrack

/// Постер «Поделиться» проверяется ПИКСЕЛЕМ, и только так.
///
/// Всё, что он делает, — это «положить одно поверх другого в правильном
/// месте»: туман поверх снимка, дыра коридора в тумане, печать над своей
/// дорогой. Ни одно из трёх не выражается ни возвращаемым значением, ни
/// состоянием — сломанное лежит в картинке и выглядит как картинка. Ровно
/// поэтому композиция вынесена в чистую функцию: снимок сюда приходит
/// нарисованным руками (1:1, без сети), а тест читает байты.
///
/// Белый «снимок» — не лень, а инструмент: под туманом он не виден вовсе, а в
/// прожжённом коридоре виден весь. Разница между «в коридоре» и «в тумане»
/// на нём максимальна и не зависит ни от плиток Apple, ни от сети.
final class AtlasSharePosterTests: XCTestCase {

    /// Палитра мглы ПРИШПИЛИВАЕТСЯ к ночной на время прогона.
    ///
    /// С «мглы по теме» её выбирает `MyMapRepresentable` по трейту своей вью,
    /// то есть по ВНЕШНЕМУ ВИДУ СИМУЛЯТОРА, на котором поднялось хост-
    /// приложение. А оба пиксельных утверждения здесь написаны про ТЁМНУЮ
    /// мглу: белая подпись читается только на тёмной плашке, а коридор
    /// светлее тумана только пока туман тёмный. На светлом симуляторе плашка
    /// `.mist` сама светлее порога 200 (0xDC…0xEA), и «подписи нет» падало
    /// там, где подпись есть.
    ///
    /// Возвращается она в `tearDown` — глобалка, оставленная тестом, роняет
    /// СОСЕДЕЙ, а не его самого.
    private var paletteBeforeTest: FogVeilPainter.Palette?

    override func setUp() {
        super.setUp()
        paletteBeforeTest = FogVeilPainter.palette
        FogVeilPainter.palette = .night
    }

    override func tearDown() {
        if let paletteBeforeTest { FogVeilPainter.palette = paletteBeforeTest }
        paletteBeforeTest = nil
        super.tearDown()
    }

    // MARK: Данные

    /// Одна прямая дорога вдоль параллели — в картинке это горизонтальная
    /// линия, поперёк которой удобно читать пиксели.
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
    private func fakeSnapshot(
        size: CGSize = AtlasSharePoster.renderPointSize, scale: CGFloat = 1
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func seal(
        _ kind: DiscoveryKind, at coordinate: CLLocationCoordinate2D, key: String = "k"
    ) -> Discovery {
        Discovery(
            kind: kind, key: key, tripId: UUID(), coordinate: coordinate,
            foundAt: Date(timeIntervalSince1970: 1_780_000_000), symbol: .lighthouse)
    }

    // MARK: Чтение пикселей

    /// BGRA — тот же порядок байт, что у `FogVeilPainterTests`.
    private struct Raster {
        let data: [UInt8]
        let width: Int
        let height: Int

        func pixel(x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
            guard x >= 0, y >= 0, x < width, y < height else { return (0, 0, 0) }
            let i = (y * width + x) * 4
            return (Int(data[i + 2]), Int(data[i + 1]), Int(data[i]))
        }

        func luminance(x: Int, y: Int) -> Double {
            let p = pixel(x: x, y: y)
            return 0.299 * Double(p.r) + 0.587 * Double(p.g) + 0.114 * Double(p.b)
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

    /// Сколько пикселей в окне похожи на цвет с допуском по каналу.
    private func matches(
        _ raster: Raster, colour: UIColor, tolerance: Int, in box: CGRect
    ) -> Int {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        let want = (r: Int(r * 255), g: Int(g * 255), b: Int(b * 255))
        var count = 0
        for y in Int(box.minY)..<Int(box.maxY) {
            for x in Int(box.minX)..<Int(box.maxX) {
                let p = raster.pixel(x: x, y: y)
                if abs(p.r - want.r) <= tolerance,
                   abs(p.g - want.g) <= tolerance,
                   abs(p.b - want.b) <= tolerance { count += 1 }
            }
        }
        return count
    }

    // MARK: Проекция

    /// Окно и мировой прямоугольник обязаны переводиться друг в друга без
    /// потерь: одно уезжает в `MKMapSnapshotter`, второе считает места печатей.
    /// Разъедься они — печать встала бы мимо своей дороги, а заметить это
    /// можно было бы только глазами на готовой картинке.
    func testRegionAndMapRectAreInverseOfEachOther() {
        guard let rect = AtlasSharePoster.frame(for: straightLayer()) else {
            return XCTFail("окно обязано посчитаться")
        }
        let back = AtlasSharePoster.mapRect(for: AtlasSharePoster.region(for: rect))
        let tolerance = rect.width * 1e-6
        XCTAssertEqual(back.minX, rect.minX, accuracy: tolerance)
        XCTAssertEqual(back.minY, rect.minY, accuracy: tolerance)
        XCTAssertEqual(back.width, rect.width, accuracy: tolerance)
        XCTAssertEqual(back.height, rect.height, accuracy: tolerance)
    }

    /// Пропорция окна = пропорция картинки. Снапшоттер раздвигает окно сам и
    /// молча, а проекция печатей считается по тому, которое дали ему мы.
    func testFrameTakesTheAspectOfThePoster() {
        guard let rect = AtlasSharePoster.frame(for: straightLayer()) else {
            return XCTFail("окно обязано посчитаться")
        }
        let wanted = Double(
            AtlasSharePoster.renderPointSize.width / AtlasSharePoster.renderPointSize.height)
        XCTAssertEqual(rect.width / rect.height, wanted, accuracy: 1e-6)
    }

    func testEmptyLayerHasNoFrameAtAll() {
        XCTAssertNil(AtlasSharePoster.frame(for: .empty))
    }

    // MARK: Композиция

    func testPosterKeepsTheSizeOfItsSnapshot() {
        let layer = straightLayer()
        guard let rect = AtlasSharePoster.frame(for: layer) else {
            return XCTFail("окно обязано посчитаться")
        }
        let poster = AtlasSharePoster.render(
            snapshot: fakeSnapshot(), region: AtlasSharePoster.region(for: rect),
            layer: layer, seals: [], caption: "Атлас", scale: 1)

        XCTAssertEqual(poster.size, AtlasSharePoster.renderPointSize)
        XCTAssertEqual(poster.cgImage?.width, Int(AtlasSharePoster.renderPointSize.width))
        XCTAssertEqual(poster.cgImage?.height, Int(AtlasSharePoster.renderPointSize.height))
    }

    /// Главное обещание постера: он показывает ОТКРЫТОЕ, а не карту мира.
    ///
    /// Под белым «снимком» это читается напрямую — в коридоре виден белый, в
    /// тумане не видно ничего. Порог 60 по яркости, потому что мерить надо
    /// разницу «дыра/не дыра», а не оттенок: заливка вуали держится около 15
    /// по яркости, белый снимок — 255, и любая сработавшая дыра даёт разрыв в
    /// разы больше порога.
    func testCorridorIsLighterThanTheFogAroundIt() {
        let layer = straightLayer()
        guard let rect = AtlasSharePoster.frame(for: layer) else {
            return XCTFail("окно обязано посчитаться")
        }
        let region = AtlasSharePoster.region(for: rect)
        let poster = AtlasSharePoster.render(
            snapshot: fakeSnapshot(), region: region, layer: layer, seals: [],
            caption: "Атлас", scale: 1)
        guard let raster = raster(of: poster) else { return XCTFail("пиксели обязаны читаться") }

        let centre = AtlasSharePoster.project(
            middle, rect: rect, size: AtlasSharePoster.renderPointSize)
        // Поперёк дороги: коридор ≈ 100 м, то есть больше десятка точек на
        // этом масштабе, — берём самый светлый пиксель полосы в ±8.
        var brightest = 0.0
        for dy in -8...8 {
            brightest = max(brightest, raster.luminance(x: Int(centre.x), y: Int(centre.y) + dy))
        }
        // Туман — четверть высоты выше дороги, заведомо мимо неё.
        let fog = raster.luminance(x: Int(centre.x), y: Int(centre.y) - 220)

        print("[poster] коридор \(brightest) · туман \(fog)")
        // Потолок — из КОНСТАНТ кисти, а не число: тон тумана подняли в
        // «Атлас как атлас», и вписанные 60 упали бы, ничего не объяснив.
        // Потолок считается ПО КОМПОЗИЦИИ: мгла полупрозрачна («ночная
        // карта»), и на белом холсте теста сквозь неё светит сам холст.
        // Сравнивать с яркостью одного лишь цвета мглы стало нечего.
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        FogVeilPainter.veilColorBottom.getRed(&r, green: &g, blue: &b, alpha: &a)
        let veil = (0.299 * r + 0.587 * g + 0.114 * b) * 255
        let alpha = FogVeilPainter.veilAlpha
        let ceiling = veil * alpha + 255 * (1 - alpha) + 12
        XCTAssertLessThan(fog, ceiling, "туман обязан оставаться тёмным: \(fog)")
        XCTAssertGreaterThan(
            brightest, fog + 60,
            "коридор не прожжён: \(brightest) против тумана \(fog)")
    }

    /// Печать стоит ТАМ, где её проецирует карта, и кольцом своего вида.
    ///
    /// Цвет кольца — единственное, чем вид находки отличается на картинке
    /// (`SealPainter.ring`), и проверять его глазами на тумане значит не
    /// проверять вовсе.
    func testSealLandsOnItsPlaceWithItsRingColour() {
        let layer = straightLayer()
        guard let rect = AtlasSharePoster.frame(for: layer) else {
            return XCTFail("окно обязано посчитаться")
        }
        let region = AtlasSharePoster.region(for: rect)
        let poster = AtlasSharePoster.render(
            snapshot: fakeSnapshot(), region: region, layer: layer,
            seals: [seal(.secret, at: middle)], caption: "Атлас", scale: 1)
        guard let raster = raster(of: poster) else { return XCTFail("пиксели обязаны читаться") }

        let centre = AtlasSharePoster.project(
            middle, rect: rect, size: AtlasSharePoster.renderPointSize)
        let size = AtlasSharePoster.sealSize
        let box = CGRect(x: centre.x - size / 2 - 2, y: centre.y - size / 2 - 2,
                         width: size + 4, height: size + 4)
        let gold = matches(raster, colour: SealPainter.ring(for: .secret), tolerance: 24, in: box)

        print("[poster] пикселей кольца печати: \(gold)")
        XCTAssertGreaterThan(gold, 20, "кольца печати на её месте нет")
    }

    /// Ненайденного на постере нет. Список печатей приходит уже только
    /// найденным, и постер ничего к нему не добавляет — пустой список обязан
    /// давать картинку БЕЗ единой печати, а не «печати по умолчанию».
    func testWithoutSealsNothingIsStamped() {
        let layer = straightLayer()
        guard let rect = AtlasSharePoster.frame(for: layer) else {
            return XCTFail("окно обязано посчитаться")
        }
        let region = AtlasSharePoster.region(for: rect)
        let poster = AtlasSharePoster.render(
            snapshot: fakeSnapshot(), region: region, layer: layer, seals: [],
            caption: "Атлас", scale: 1)
        guard let raster = raster(of: poster) else { return XCTFail("пиксели обязаны читаться") }

        let whole = CGRect(x: 0, y: 0, width: raster.width, height: raster.height)
        for kind in [DiscoveryKind.secret, .riddle, .milestone] {
            XCTAssertEqual(
                matches(raster, colour: SealPainter.ring(for: kind), tolerance: 12, in: whole), 0,
                "на постере без находок нашлось кольцо \(kind.rawValue)")
        }
    }

    /// Подпись действительно печатается, и печатается В ПЛАШКЕ.
    ///
    /// Белый текст — единственное светлое, что есть внизу постера: сама
    /// плашка идёт в цвет вуали, а карта под ней закрыта туманом. Марка
    /// («TripTrack») стоит на 45 % белого, то есть до порога 200 не
    /// дотягивается, и пустая подпись обязана давать ноль.
    func testCaptionIsPrintedInsideTheStrip() {
        let layer = straightLayer()
        guard let rect = AtlasSharePoster.frame(for: layer) else {
            return XCTFail("окно обязано посчитаться")
        }
        let region = AtlasSharePoster.region(for: rect)
        func brightPixels(caption: String) -> Int {
            let poster = AtlasSharePoster.render(
                snapshot: fakeSnapshot(), region: region, layer: layer, seals: [],
                caption: caption, scale: 1)
            guard let raster = raster(of: poster) else { return -1 }
            var count = 0
            let top = Int(AtlasSharePoster.renderPointSize.height - AtlasSharePoster.captionHeight)
            for y in top..<raster.height {
                for x in 0..<raster.width {
                    let p = raster.pixel(x: x, y: y)
                    if p.r > 200, p.g > 200, p.b > 200 { count += 1 }
                }
            }
            return count
        }

        let printed = brightPixels(caption: "Атлас · 1 910 км открыто · 4 знака")
        let empty = brightPixels(caption: "")
        print("[poster] светлых пикселей подписи: \(printed), без подписи: \(empty)")
        XCTAssertGreaterThan(printed, 200, "подписи на постере нет")
        XCTAssertEqual(empty, 0, "без подписи в плашке не должно быть текста")
    }

    /// Подпись читается при ЛЮБОЙ палитре — в том числе светлой.
    ///
    /// Рампа под ней брала цвет у тумана (`veilColorBottom`), и под светлой
    /// «дымкой» подпись была бледной, а слово «TripTrack» пропадало совсем:
    /// владелец прислал такой постер 23 сентября. Подпись — хром поверх
    /// картинки, а не продолжение тумана; проверяется это контрастом белого
    /// текста к тому, что под ним, на самой светлой карте, какая бывает.
    func testCaptionReadsOnALightPaletteToo() {
        let layer = straightLayer()
        guard let rect = AtlasSharePoster.frame(for: layer) else {
            return XCTFail("окно обязано посчитаться")
        }
        let region = AtlasSharePoster.region(for: rect)

        for (name, palette) in [("ночь", FogVeilPainter.Palette.night), ("дымка", .mist)] {
            FogVeilPainter.palette = palette
            let poster = AtlasSharePoster.render(
                snapshot: fakeSnapshot(), region: region, layer: layer,
                seals: [], caption: "Атлас · Открыто: 181 миля", scale: 1)
            guard let raster = raster(of: poster) else { return XCTFail("растр не собрался") }

            // Полоса вокруг слова «TripTrack»: самая нижняя и самая бледная
            // часть рампы — если читается она, читается и строка выше.
            let bottom = raster.height - 1
            let band = max(0, bottom - 40)...bottom
            var sum = 0.0, count = 0.0
            for y in band {
                for x in 0..<raster.width {
                    let p = raster.pixel(x: x, y: y)
                    sum += 0.299 * Double(p.r) + 0.587 * Double(p.g) + 0.114 * Double(p.b)
                    count += 1
                }
            }
            let mean = sum / count
            print("[poster] яркость под подписью (\(name)): \(Int(mean))")
            // Белый текст на 0.72 альфы: контраст к чистому белому — больше
            // 4.5:1, порог читаемости. Выше 110 это уже не выполняется.
            XCTAssertLessThan(mean, 110,
                              "под подписью обязано быть темно при любой палитре (\(name))")
        }
    }

    /// Строка подписи собирается из тех же слов, что шапка «Атласа», а ноль
    /// знаков не печатается вовсе.
    func testCaptionCopySkipsAZeroSealCount() {
        let with = AppStrings.posterCaption(.ru, distance: "1 910 км", seals: 4)
        XCTAssertTrue(with.hasPrefix(AppStrings.myMapTitle(.ru)), with)
        XCTAssertTrue(with.contains("1 910 км"), with)
        XCTAssertTrue(with.contains(AppStrings.nounSeals(.ru, 4)), with)

        let without = AppStrings.posterCaption(.ru, distance: "1 910 км", seals: 0)
        XCTAssertFalse(without.contains(AppStrings.nounSeals(.ru, 0)), without)
        XCTAssertFalse(without.contains("{distance}"), without)

        for lang in LanguageManager.Language.allCases {
            let line = AppStrings.posterCaption(lang, distance: "10 km", seals: 2)
            XCTAssertFalse(line.contains("{distance}"), "\(lang.rawValue): токен не подставлен")
            XCTAssertFalse(AppStrings.shareRendering(lang).isEmpty, lang.rawValue)
        }
    }

    /// Пустая сетка MapKit узнаётся и постером не становится.
    ///
    /// Снимок «пришёл» и при отсутствии плиток — светлой подложкой в клетку
    /// (симулятор без доступа к плиткам отдаёт ровно её). Под туманом её не
    /// видно, а в коридорах она белая: постер с белыми дорогами по чёрному не
    /// похож ни на карту, ни на экран.
    func testBlankMapCanvasIsRecognisedAndRefused() {
        XCTAssertTrue(AtlasSharePoster.looksUnrendered(fakeSnapshot(
            size: CGSize(width: 120, height: 200))))

        // Тёмная карта — то, что приходит на телефоне с сетью.
        let dark = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 200)).image { ctx in
            UIColor(white: 0.12, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 200))
        }
        XCTAssertFalse(AtlasSharePoster.looksUnrendered(dark))

        // Светлая, но НЕ ровная — настоящая карта в светлой теме: дороги,
        // вода, подписи. Постер по ней собрать можно, и съедать его нельзя.
        let busy = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 200)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 200))
            UIColor(white: 0.35, alpha: 1).setFill()
            for i in 0..<10 {
                ctx.fill(CGRect(x: 0, y: CGFloat(i) * 20, width: 120, height: 9))
            }
        }
        XCTAssertFalse(AtlasSharePoster.looksUnrendered(busy))
    }

    /// Та же дверь, которой пользуется мини-карта решённой загадки
    /// (`RiddleMiniMap` в `DiscoveryCardSheet`): «этот снимок можно показать?».
    /// Три ответа — нет снимка, есть но пустой, есть настоящий.
    func testUsableSnapshotRefusesNothingAndBlankGrid() {
        XCTAssertNil(AtlasSharePoster.usableSnapshot(nil))
        XCTAssertNil(AtlasSharePoster.usableSnapshot(
            fakeSnapshot(size: CGSize(width: 120, height: 200))))

        let dark = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 200)).image { ctx in
            UIColor(white: 0.12, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 200))
        }
        XCTAssertNotNil(AtlasSharePoster.usableSnapshot(dark))
    }

    // MARK: Кадр

    /// Кадр `w070_w4_poster.png` — настоящими плитками Apple, а не белым
    /// холстом: снимок карты и есть та половина постера, которую надо увидеть
    /// глазами.
    ///
    /// ВНИМАНИЕ: на симуляторе плитки Apple не приходят (проверено пробой —
    /// снимок это светлая сетка с «Maps» в углу), поэтому в прожжённых
    /// коридорах на кадре видна БЕЛАЯ подложка вместо тёмной карты. На
    /// телефоне с сетью там карта; `make` такой снимок вообще не пропустит
    /// (`looksUnrendered`), а кадр собирается мимо него — иначе показать
    /// композицию было бы нечем.
    ///
    /// Пишется в папку из `TT_SHOTS_DIR` (её задаёт прогон) и прикладывается
    /// к результату теста. Ни сети, ни папки — тест молча выходит: постер
    /// проверяют тесты выше, а кадр это артефакт, а не сторож.
    func testRendersTheShotPoster() async throws {
        let dir = ProcessInfo.processInfo.environment["TT_SHOTS_DIR"]
            ?? ProcessInfo.processInfo.environment["TEST_RUNNER_TT_SHOTS_DIR"]
        let layer = Self.demoLayer()
        guard let rect = AtlasSharePoster.frame(for: layer) else {
            return XCTFail("окно обязано посчитаться")
        }
        let region = AtlasSharePoster.region(for: rect)
        guard let snapshot = await AtlasSharePoster.snapshot(region: region) else {
            throw XCTSkip("плитки карты не пришли — снимать нечего")
        }
        let poster = AtlasSharePoster.render(
            snapshot: snapshot, region: region, layer: layer, seals: Self.demoSeals(),
            caption: AppStrings.posterCaption(
                .ru, distance: "1 910 км", seals: Self.demoSeals().count),
            scale: AtlasSharePoster.renderScale)

        let attachment = XCTAttachment(image: poster)
        attachment.name = "w070_w4_poster"
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let dir, let png = poster.pngData() else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("w070_w4_poster.png")
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: dir), withIntermediateDirectories: true)
        try png.write(to: url)
        print("[poster] кадр записан: \(url.path)")
    }

    /// Проезженная сеть под Краснодаром — форма одного человека, как в
    /// `MapRenderCostTests`.
    static func demoLayer() -> RevealedLayer {
        var runs: [[CLLocationCoordinate2D]] = []
        for pass in 0..<6 {
            let coords = (0..<160).map { i -> CLLocationCoordinate2D in
                let t = Double(i) / 159
                let phase = Double(i) * 0.5 + Double(pass) * 1.3
                return CLLocationCoordinate2D(
                    latitude: 45.00 + 0.09 * t * Double(pass % 3 + 1) / 2
                        + sin(phase) * 0.0006,
                    longitude: 38.95 + 0.14 * t + cos(phase) * 0.0006
                )
            }
            runs.append(coords)
        }
        return RevealedLayer.build(runs: runs, cellCount: runs.count * 160, atlas: nil)
    }

    static func demoSeals() -> [Discovery] {
        [
            Discovery(kind: .secret, key: "komsomolsky", tripId: UUID(),
                      coordinate: CLLocationCoordinate2D(latitude: 45.03, longitude: 38.99),
                      foundAt: Date(timeIntervalSince1970: 1_780_000_000), symbol: .region),
            Discovery(kind: .riddle, key: "pass-1", tripId: UUID(),
                      coordinate: CLLocationCoordinate2D(latitude: 45.06, longitude: 39.04),
                      foundAt: Date(timeIntervalSince1970: 1_780_100_000), symbol: .pass),
            Discovery(kind: .milestone, key: "easternmost:2026-09-16", tripId: UUID(),
                      coordinate: CLLocationCoordinate2D(latitude: 45.09, longitude: 39.08),
                      foundAt: Date(timeIntervalSince1970: 1_780_200_000), symbol: .extreme),
        ]
    }
}
