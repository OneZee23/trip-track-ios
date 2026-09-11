import XCTest
import UIKit
@testable import TripTrack

/// Три слоя машинки на карте и их покраска.
///
/// Собрать картинку здесь нельзя: юнит-тесты идут без хост-приложения, и
/// `UIImage(named:)` смотрит в бандл раннера, где каталога нет (о том же
/// предупреждает комментарий в `project.yml`). Поэтому проверяется то, что
/// ломается молча: слой, забытый в гите, слой, переэкспортированный в другом
/// размере, и цвет, ушедший в крайность.
final class MapCarMarkerTests: XCTestCase {

    private static let repoRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }()

    private static let layers = ["map_car_body", "map_car_shade", "map_car_ink"]

    private func png(_ layer: String) throws -> Data {
        let url = Self.repoRoot
            .appendingPathComponent("TripTrack/Resources/Assets.xcassets")
            .appendingPathComponent("\(layer).imageset")
            .appendingPathComponent("\(layer).png")
        return try Data(contentsOf: url)
    }

    /// Размер из заголовка PNG — без UIKit, потому что каталога в бандле теста
    /// нет, а файл на диске есть.
    private func size(ofPNG data: Data) -> (width: Int, height: Int)? {
        guard data.count > 24 else { return nil }
        func be32(_ offset: Int) -> Int {
            (0..<4).reduce(0) { $0 << 8 | Int(data[data.startIndex + offset + $1]) }
        }
        return (be32(16), be32(20))
    }

    /// Слой, не доехавший до гита, превращает маркер в ничто: сборка молчит,
    /// `UIImage(named:)` возвращает nil, а карта остаётся со штатным кружком.
    func testEveryLayerShipsWithTheApp() throws {
        for layer in Self.layers {
            XCTAssertNoThrow(try png(layer), "слой \(layer) не лежит в каталоге приложения")
        }
    }

    /// Центры совпадают до пикселя только пока холсты одинаковы. Слой,
    /// переэкспортированный в другом размере, уводит контур относительно
    /// краски — и на маленьком маркере это выглядит как грязь по кромке.
    func testAllThreeLayersShareOneCanvas() throws {
        let sizes = try Self.layers.map { layer -> (width: Int, height: Int) in
            guard let size = size(ofPNG: try png(layer)) else {
                XCTFail("\(layer).png не читается как PNG")
                return (0, 0)
            }
            return size
        }
        for (layer, size) in zip(Self.layers, sizes) {
            XCTAssertEqual(size.width, size.height, "\(layer): холст не квадратный")
            XCTAssertEqual(size.width, sizes[0].width, "\(layer): другой холст, центры разъедутся")
        }
    }

    /// Чистый чёрный сливается с собственным контуром, чистый белый — с белым
    /// ореолом. Оба цвета в гараже есть, и оба самые частые на дорогах.
    func testPaintStaysInsideTheReadableCorridor() {
        for color in VehicleAvatar.colors {
            var brightness: CGFloat = 0, hue: CGFloat = 0, saturation: CGFloat = 0, alpha: CGFloat = 0
            let paint = MapCarMarker.paint(colorName: color)
            XCTAssertTrue(paint.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha))
            XCTAssertGreaterThanOrEqual(brightness, MapCarMarker.minBrightness - 0.0001, "\(color) слишком тёмный")
            XCTAssertLessThanOrEqual(brightness, MapCarMarker.maxBrightness + 0.0001, "\(color) слишком светлый")
        }
    }

    /// Зажимается СВЕТЛОТА, а не цвет: красная машина обязана остаться красной.
    func testClampingKeepsTheHue() {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(MapCarMarker.paint(colorName: "red")
            .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha))
        let (r, g, b) = VehicleAvatar.swatch("red")
        var swatchHue: CGFloat = 0, s2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        XCTAssertTrue(UIColor(red: r, green: g, blue: b, alpha: 1)
            .getHue(&swatchHue, saturation: &s2, brightness: &b2, alpha: &a2))
        XCTAssertEqual(hue, swatchHue, accuracy: 0.001)
    }

    /// Незнакомый цвет — это цвет гаража по умолчанию, а не чёрный прямоугольник.
    func testUnknownColourFallsBackToTheGarageDefault() {
        XCTAssertEqual(
            MapCarMarker.paint(colorName: "chartreuse"),
            MapCarMarker.paint(colorName: VehicleAvatar.defaultColor)
        )
    }

    // MARK: - Состояния

    /// Пауза гасит краску, но не стирает её: машина обязана остаться собой,
    /// иначе «на паузе» и «нет сигнала» станут одним и тем же серым пятном.
    func testPauseDimsThePaintButKeepsIt() {
        let normal = saturation(of: MapCarMarker.paint(colorName: "red"))
        let paused = saturation(of: MapCarMarker.paint(
            colorName: "red", saturation: MapCarMarker.Mood.paused.saturation
        ))
        XCTAssertLessThan(paused, normal)
        XCTAssertGreaterThan(paused, 0, "на паузе краска не должна пропадать совсем")
        XCTAssertEqual(MapCarMarker.Mood.paused.alpha, 1, "пауза не про прозрачность")
    }

    /// «Нет сигнала» — цвета нет вовсе, и маркер наполовину прозрачен. Две
    /// разные вещи: цвет говорит «не знаю какой», прозрачность — «не знаю где».
    func testLostSignalHasNoColourLeft() {
        for color in VehicleAvatar.colors {
            let paint = MapCarMarker.paint(
                colorName: color, saturation: MapCarMarker.Mood.lost.saturation
            )
            XCTAssertEqual(saturation(of: paint), 0, accuracy: 0.0001, "\(color) сохранил цвет")
        }
        XCTAssertLessThan(MapCarMarker.Mood.lost.alpha, 1)
        XCTAssertGreaterThan(MapCarMarker.Mood.lost.alpha, 0.3, "совсем невидимый маркер — потеря места")
    }

    /// Гашение насыщенности идёт ПОСЛЕ зажима светлоты, поэтому серая машина
    /// остаётся видимой машиной, а не чёрным или белым прямоугольником.
    func testEveryMoodStaysInsideTheReadableCorridor() {
        for mood in [MapCarMarker.Mood.normal, .paused, .lost] {
            for color in VehicleAvatar.colors {
                let paint = MapCarMarker.paint(colorName: color, saturation: mood.saturation)
                var hue: CGFloat = 0, sat: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
                XCTAssertTrue(paint.getHue(&hue, saturation: &sat, brightness: &brightness, alpha: &alpha))
                XCTAssertGreaterThanOrEqual(brightness, MapCarMarker.minBrightness - 0.0001,
                                            "\(color)/\(mood.rawValue) слишком тёмный")
                XCTAssertLessThanOrEqual(brightness, MapCarMarker.maxBrightness + 0.0001,
                                         "\(color)/\(mood.rawValue) слишком светлый")
            }
        }
    }

    // MARK: - Схлопывание на мелком зуме

    /// Порог меряется в МЕТРАХ НА ПУНКТ, и смысл у него один: маркер уходит
    /// прежде, чем начнёт закрывать собой километры дороги.
    func testMarkerLeavesBeforeItCoversAKilometre() {
        XCTAssertGreaterThan(Double(MapCarMarker.side) * MapCarMarker.collapseMetersPerPoint, 1000)
    }

    /// Ниже порога — машина, выше — точка.
    func testCollapseFollowsTheScale() {
        XCTAssertFalse(MapCarMarker.collapsed(
            metersPerPoint: MapCarMarker.collapseMetersPerPoint - 1, wasCollapsed: false))
        XCTAssertTrue(MapCarMarker.collapsed(
            metersPerPoint: MapCarMarker.collapseMetersPerPoint + 1, wasCollapsed: false))
    }

    /// Обратно машина возвращается раньше, чем ушла. Без разрыва щипок
    /// пальцами моргал бы точкой несколько раз за жест — и это ровно тот
    /// случай, который глазами на устройстве уже не разберёшь.
    func testCollapseHasHysteresis() {
        XCTAssertLessThan(MapCarMarker.expandMetersPerPoint, MapCarMarker.collapseMetersPerPoint)
        let between = (MapCarMarker.expandMetersPerPoint + MapCarMarker.collapseMetersPerPoint) / 2
        XCTAssertTrue(MapCarMarker.collapsed(metersPerPoint: between, wasCollapsed: true),
                      "в разрыве схлопнутый остаётся схлопнутым")
        XCTAssertFalse(MapCarMarker.collapsed(metersPerPoint: between, wasCollapsed: false),
                       "в разрыве развёрнутый остаётся развёрнутым")
    }

    /// Камера реплея, едущая за машиной, показывает 1400 м поперёк экрана —
    /// это около трёх с половиной метров на пункт. Машинка там обязана быть
    /// машинкой: схлопнуться в точку ровно в реплее значило бы отменить его.
    func testFollowingCameraNeverCollapsesTheCar() {
        let across: Double = 1400
        let screenPoints: Double = 393
        XCTAssertFalse(MapCarMarker.collapsed(
            metersPerPoint: across / screenPoints, wasCollapsed: true
        ))
    }

    /// Карта ещё не сказала масштаб — решение не меняется. Ноль здесь значит
    /// «не знаю», и принимать по нему решение нельзя ни в какую сторону.
    func testUnknownScaleChangesNothing() {
        XCTAssertTrue(MapCarMarker.collapsed(metersPerPoint: 0, wasCollapsed: true))
        XCTAssertFalse(MapCarMarker.collapsed(metersPerPoint: 0, wasCollapsed: false))
    }

    /// Точка, в которую маркер схлопывается, — с ОБВОДКОЙ. Без белого кольца
    /// тёмная точка тонет в дороге под собой, и схлопывание из «вижу, где
    /// машина» превращается в «машина пропала».
    func testCollapsedDotKeepsItsOutline() {
        let side = MapCarMarker.dotDiameter
        let image = MapCarMarker.dot(colorName: "red")
        XCTAssertEqual(image.size.width, side)
        XCTAssertEqual(image.size.height, side)

        guard let centre = pixel(image, at: CGPoint(x: side / 2, y: side / 2), side: side),
              let rim = pixel(image, at: CGPoint(x: side / 2, y: 1), side: side) else {
            return XCTFail("точка не читается как растр")
        }
        XCTAssertGreaterThan(centre.r, centre.b + 60, "в середине должна быть краска машины")
        XCTAssertGreaterThan(rim.r, 200, "кольцо не белое")
        XCTAssertGreaterThan(rim.g, 200, "кольцо не белое")
        XCTAssertGreaterThan(rim.b, 200, "кольцо не белое")
    }

    // MARK: - Мелочи

    private func saturation(of color: UIColor) -> CGFloat {
        var hue: CGFloat = 0, sat: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &sat, brightness: &brightness, alpha: &alpha)
        return sat
    }

    private func pixel(
        _ image: UIImage, at point: CGPoint, side: CGFloat
    ) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        let size = Int(side)
        var data = [UInt8](repeating: 0, count: size * size * 4)
        guard let cg = image.cgImage else { return nil }
        let ok: Bool = data.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: size, height: size, bitsPerComponent: 8,
                bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard ok else { return nil }
        let index = (Int(point.y) * size + Int(point.x)) * 4
        guard index + 3 < data.count else { return nil }
        return (data[index], data[index + 1], data[index + 2], data[index + 3])
    }
}
