import XCTest
import UIKit
import CoreLocation
@testable import TripTrack

/// Медальон печати — по пикселям.
///
/// Цвет кольца это ЕДИНСТВЕННОЕ, чем вид находки отличается на карте: золото —
/// авторский секрет, бирюза — загадка, тёплый — веха. Перепутанные местами
/// цвета не роняют ни сборку, ни один поведенческий тест, а на тумане их
/// различает только глаз — поэтому здесь читается сам пиксель.
final class SealPainterTests: XCTestCase {

    // MARK: - Пиксели

    /// Цвет точки картинки. `premultipliedLast` с непрозрачным пикселем даёт
    /// компоненты как есть — кольцо непрозрачно по построению.
    private func pixel(_ image: UIImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int)? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let offset = (y * width + x) * 4
        return (Int(data[offset]), Int(data[offset + 1]),
                Int(data[offset + 2]), Int(data[offset + 3]))
    }

    /// Точка ровно на осевой линии кольца: радиус кольца —
    /// `(size − ringWidth) / 2`, то есть крайний столбец пикселей при
    /// `scale = 1`.
    private func ringPixel(kind: DiscoveryKind) -> (r: Int, g: Int, b: Int, a: Int)? {
        let size: CGFloat = 26
        let image = SealPainter.image(kind: kind, symbol: .lighthouse, size: size, scale: 1)
        return pixel(image, x: Int(size) - 1, y: Int(size) / 2)
    }

    private func assertNear(
        _ got: (r: Int, g: Int, b: Int, a: Int)?, _ expected: UIColor,
        _ message: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let got else { return XCTFail("нет пикселя: \(message)", file: file, line: line) }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        expected.getRed(&r, green: &g, blue: &b, alpha: &a)
        let want = (Int(r * 255), Int(g * 255), Int(b * 255))
        let tolerance = 14
        XCTAssertLessThanOrEqual(abs(got.r - want.0), tolerance, "\(message): красный", file: file, line: line)
        XCTAssertLessThanOrEqual(abs(got.g - want.1), tolerance, "\(message): зелёный", file: file, line: line)
        XCTAssertLessThanOrEqual(abs(got.b - want.2), tolerance, "\(message): синий", file: file, line: line)
        XCTAssertGreaterThan(got.a, 200, "\(message): кольцо непрозрачно", file: file, line: line)
    }

    // MARK: - Размер

    func testImageIsSquareAtTheAskedSizeAndScale() {
        let image = SealPainter.image(kind: .riddle, symbol: .bridge, size: 26, scale: 2)
        XCTAssertEqual(image.size.width, 26)
        XCTAssertEqual(image.size.height, 26)
        XCTAssertEqual(image.scale, 2)
        XCTAssertEqual(image.cgImage?.width, 52, "масштаб 2 — это 52 пикселя на 26 точек")
    }

    func testDefaultSizeIsTheOneTheMapDraws() {
        let image = SealPainter.image(kind: .secret, symbol: .pass, scale: 1)
        XCTAssertEqual(image.size.width, SealPainter.size)
    }

    // MARK: - Кольцо

    func testSecretRingIsGold() {
        assertNear(ringPixel(kind: .secret),
                   UIColor(red: 0xF5 / 255, green: 0xBE / 255, blue: 0x1E / 255, alpha: 1),
                   "секрет — золото #f5be1e")
    }

    func testRiddleRingIsTurquoise() {
        assertNear(ringPixel(kind: .riddle),
                   UIColor(red: 0x50 / 255, green: 0xBE / 255, blue: 0xD2 / 255, alpha: 1),
                   "загадка — бирюза #50bed2")
    }

    func testMilestoneRingIsWarm() {
        assertNear(ringPixel(kind: .milestone),
                   UIColor(red: 0xF0 / 255, green: 0xA0 / 255, blue: 0x70 / 255, alpha: 1),
                   "веха — тёплый #f0a070")
    }

    /// Середина медальона — тёмный диск, а не кольцо и не белизна: печать
    /// «вдавлена в туман», и светлый центр читался бы как обычный пин.
    func testCentreIsTheDarkDisc() {
        let image = SealPainter.image(kind: .riddle, symbol: .dam, size: 26, scale: 1)
        // Чуть в стороне от символа — он белый и стоит ровно в середине.
        guard let point = pixel(image, x: 4, y: 13) else { return XCTFail("нет пикселя") }
        XCTAssertLessThan(point.r, 70)
        XCTAssertLessThan(point.g, 70)
        XCTAssertLessThan(point.b, 80)
        XCTAssertGreaterThan(point.a, 200)
    }

    // MARK: - Кэш

    /// Одна и та же печать не рисуется дважды: `MKAnnotationView` собирает
    /// себя на каждом переиспользовании, а их на «Атласе» столько, сколько
    /// печатей на экране.
    func testSameSealComesBackFromTheCache() {
        let first = SealPainter.image(kind: .milestone, symbol: .region, size: 26, scale: 2)
        let second = SealPainter.image(kind: .milestone, symbol: .region, size: 26, scale: 2)
        XCTAssertTrue(first === second)
    }

    func testDifferentKindIsADifferentImage() {
        let riddle = SealPainter.image(kind: .riddle, symbol: .region, size: 26, scale: 2)
        let milestone = SealPainter.image(kind: .milestone, symbol: .region, size: 26, scale: 2)
        XCTAssertFalse(riddle === milestone)
    }

    // MARK: - Кластер

    /// Горсть печатей носит цвет БОЛЬШИНСТВА, а ничью забирает самое редкое.
    func testClusterTakesTheMajorityKind() {
        func seal(_ kind: DiscoveryKind) -> SealAnnotation {
            SealAnnotation(
                discovery: Discovery(
                    kind: kind, key: UUID().uuidString, tripId: UUID(),
                    coordinate: CLLocationCoordinate2D(latitude: 45, longitude: 39),
                    foundAt: Date(), symbol: .generic),
                accessibilityText: "")
        }
        XCTAssertEqual(
            SealClusterView.majorityKind(of: [seal(.riddle), seal(.riddle), seal(.milestone)]),
            .riddle)
        XCTAssertEqual(
            SealClusterView.majorityKind(of: [seal(.secret), seal(.milestone)]),
            .secret, "ничья — за самым редким")
        XCTAssertEqual(SealClusterView.majorityKind(of: []), .riddle)
    }
}
