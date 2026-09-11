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
}
