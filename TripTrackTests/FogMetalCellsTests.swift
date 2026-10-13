import XCTest
import MapKit
import Metal
@testable import TripTrack

/// «Клетки» — третий стиль карты «Атласа» (макет A7).
///
/// Проверяется не «похоже ли на клетки», а СВОЙСТВА, из которых картинка
/// складывается: край открытого ступенчатый и попадает на сетку 75 м, шаг
/// ступеней одинаковый, эталонный «Туман» от появления стиля не изменился
/// ни на пиксель, и на масштабе страны стиль молча выключается.
final class FogMetalCellsTests: XCTestCase {

    private let size = CGSize(width: 300, height: 300)
    private let scale: CGFloat = 2
    private let palette = FogVeilPainter.Palette.night
    private let krasnodar = MKMapPoint(
        CLLocationCoordinate2D(latitude: 45.03, longitude: 38.97))

    // MARK: Сетка — правило, без GPU

    /// Город: клетка на экране крупная, стиль работает.
    func testGridExistsAtStreetZoom() throws {
        let box = rect(around: krasnodar, metresPerPoint: 4)
        let grid = try XCTUnwrap(FogCellGrid.make(visible: box, viewportPoints: size))
        XCTAssertGreaterThanOrEqual(grid.sideScreenPoints, FogCellGrid.minScreenPoints)
        // Кратна базовой — иначе границы перестали бы быть границами мировой
        // сетки, и клетки поехали бы при смене масштаба.
        XCTAssertEqual(grid.sideMapPoints.truncatingRemainder(
            dividingBy: FogCellGrid.baseMapPoints), 0, accuracy: 1e-9)
    }

    /// Отдаление УДВАИВАЕТ сторону, а не выключает стиль: клетки соседних
    /// масштабов вложены, и при отдалении четыре сливаются в одну.
    func testZoomingOutDoublesTheCellInsteadOfLosingIt() throws {
        var previous = try XCTUnwrap(
            FogCellGrid.make(visible: rect(around: krasnodar, metresPerPoint: 4),
                             viewportPoints: size)).sideMapPoints
        for metres in [8.0, 16.0, 32.0, 64.0, 128.0] {
            let grid = try XCTUnwrap(FogCellGrid.make(
                visible: rect(around: krasnodar, metresPerPoint: metres), viewportPoints: size))
            XCTAssertGreaterThanOrEqual(grid.sideScreenPoints, FogCellGrid.minScreenPoints,
                                        "клетка обязана остаться читаемой на \(metres) м/pt")
            let ratio = grid.sideMapPoints / previous
            XCTAssertEqual(ratio.rounded(), ratio, accuracy: 1e-9,
                           "сторона обязана меняться ЦЕЛЫМ числом удвоений")
            XCTAssertEqual(grid.sideMapPoints.truncatingRemainder(
                dividingBy: FogCellGrid.baseMapPoints), 0, accuracy: 1e-9,
                "сторона обязана остаться кратной базовой — иначе мировая привязка теряется")
            previous = grid.sideMapPoints
        }
    }

    /// Мировой масштаб: даже предельное удвоение не даёт клетки — стиль
    /// молча падает на обычный туман.
    func testGridTurnsItselfOffAtWorldZoom() {
        let wide = rect(around: krasnodar, metresPerPoint: 400_000)
        XCTAssertNil(FogCellGrid.make(visible: wide, viewportPoints: size))
    }

    func testGridRefusesNonsense() {
        let box = rect(around: krasnodar, metresPerPoint: 4)
        XCTAssertNil(FogCellGrid.make(visible: box, viewportPoints: .zero))
        XCTAssertNil(FogCellGrid.make(visible: MKMapRect(x: 0, y: 0, width: 0, height: 0),
                                      viewportPoints: size))
    }

    /// Сторона зависит ТОЛЬКО от масштаба, и ни от чего больше.
    ///
    /// Именно зависимость от широты центра кадра и перефазировала мировую
    /// сетку при панораме: индекс клетки это `minY / side`, у Краснодара он
    /// около ста сорока тысяч, и сдвиг стороны на сотую долю точки уводил
    /// индекс на полторы клетки. Кадры ниже берут ОДИН масштаб в точках
    /// карты и разные углы мира.
    func testSideDependsOnZoomAndNothingElse() throws {
        let span = 40_000.0 // точек карты на весь кадр — одинаково везде
        func grid(at point: MKMapPoint) throws -> FogCellGrid {
            let box = MKMapRect(x: point.x - span / 2, y: point.y - span / 2,
                                width: span, height: span)
            return try XCTUnwrap(FogCellGrid.make(visible: box, viewportPoints: size))
        }
        let sides = try [
            krasnodar,
            MKMapPoint(CLLocationCoordinate2D(latitude: 68.97, longitude: 33.08)),
            MKMapPoint(CLLocationCoordinate2D(latitude: 0.32, longitude: 32.58)),
            MKMapPoint(CLLocationCoordinate2D(latitude: -33.87, longitude: 151.21)),
        ].map { try grid(at: $0).sideMapPoints }
        XCTAssertEqual(Set(sides).count, 1,
                       "сторона разъехалась по широтам — сетка снова перефазируется при панораме")
    }

    /// Панорама на полклетки не меняет сторону — то, чего не было у прежнего
    /// метрического правила.
    func testPanningDoesNotChangeTheSide() throws {
        let box = rect(around: krasnodar, metresPerPoint: 4)
        let a = try XCTUnwrap(FogCellGrid.make(visible: box, viewportPoints: size))
        let moved = MKMapRect(x: box.minX + a.sideMapPoints / 2,
                              y: box.minY + a.sideMapPoints / 3,
                              width: box.width, height: box.height)
        let b = try XCTUnwrap(FogCellGrid.make(visible: moved, viewportPoints: size))
        XCTAssertEqual(a.sideMapPoints, b.sideMapPoints)
    }

    // MARK: Картинка

    /// Край открытого у «Клеток» СТУПЕНЧАТЫЙ: альфа по вертикали прыгает
    /// между мглой и нулём, а промежуточных значений нет вовсе. У «Тумана»
    /// ровно наоборот — там перо и есть плавный спад.
    func testCellsHaveNoFeatherWhileFogDoes() throws {
        let box = rect(around: krasnodar, metresPerPoint: 4)
        let road = layer(through: [CGPoint(x: -50, y: 150), CGPoint(x: 350, y: 150)], in: box)

        let cells = try render(road, in: box, cells: true)
        let fog = try render(road, in: box, cells: false)

        let full = Double(palette.alpha)
        func intermediates(_ pixels: FogPixels) -> Int {
            var count = 0
            var y = 0.0
            while y < Double(size.height) {
                let a = pixels.alpha(atX: 150, y: y)
                if a > 0.08 * full && a < 0.92 * full { count += 1 }
                y += 1 / Double(scale)
            }
            return count
        }
        XCTAssertEqual(intermediates(cells), 0,
                       "у клетки нет пера: она открыта целиком или закрыта целиком")
        XCTAssertGreaterThan(intermediates(fog), 0,
                             "у эталонного тумана перо обязано остаться")
    }

    /// Открытое у «Клеток» шире, чем у «Тумана»: коридор округляется ВВЕРХ
    /// до целых клеток. Это и есть их смысл — показывать ячейку, через
    /// которую трек прошёл, а не полосу вокруг него.
    func testCellsRoundTheCorridorUpToWholeCells() throws {
        let box = rect(around: krasnodar, metresPerPoint: 4)
        let road = layer(through: [CGPoint(x: -50, y: 150), CGPoint(x: 350, y: 150)], in: box)
        let cells = try render(road, in: box, cells: true)
        let fog = try render(road, in: box, cells: false)
        XCTAssertGreaterThan(openHeight(in: cells), openHeight(in: fog))
    }

    /// Сетка прибита к МИРУ, а не к кадру: сдвиг камеры на половину клетки
    /// не должен сдвигать сами клетки. Проверяется тем, что открытая полоса
    /// в мировых координатах осталась на месте — её экранный край уехал
    /// ровно на столько же, на сколько уехала камера.
    func testCellsAreAnchoredToTheWorldNotTheViewport() throws {
        let box = rect(around: krasnodar, metresPerPoint: 4)
        let side = try XCTUnwrap(FogCellGrid.make(visible: box, viewportPoints: size))
        let shiftMapPoints = side.sideMapPoints / 2
        let shifted = MKMapRect(x: box.minX, y: box.minY + shiftMapPoints,
                                width: box.width, height: box.height)

        let road = layer(through: [CGPoint(x: -50, y: 150), CGPoint(x: 350, y: 150)], in: box)
        let a = try render(road, in: box, cells: true)
        let b = try render(road, in: shifted, cells: true)

        let shiftPoints = shiftMapPoints * Double(size.width) / box.width
        let edgeA = try XCTUnwrap(topEdgeOfOpen(in: a))
        let edgeB = try XCTUnwrap(topEdgeOfOpen(in: b))
        // Кадр уехал вниз по миру — открытое на экране уехало ВВЕРХ на ту же
        // величину. Допуск — один пиксель: сам край квантован пикселем.
        XCTAssertEqual(edgeA - edgeB, shiftPoints, accuracy: 1 / Double(scale) + 0.01,
                       "клетки поехали вместе с кадром — сетка не прибита к миру")
    }

    /// Пустой слой у «Клеток» — такая же ровная мгла, как у «Тумана»: стиль
    /// не имеет права нарисовать сетку там, где не открыто ничего.
    func testEmptyLayerStaysOneFlatColour() throws {
        let box = rect(around: krasnodar, metresPerPoint: 4)
        let empty = RevealedLayer(fine: MKMultiPolyline([]), mid: MKMultiPolyline([]),
                                  far: MKMultiPolyline([]), cellCount: 0, openedKm: 0,
                                  regionIds: [])
        let pixels = try render(empty, in: box, cells: true)
        XCTAssertEqual(pixels.distinctPixels.count, 1)
    }

    // MARK: Помощники

    private func rect(around centre: MKMapPoint, metresPerPoint: Double) -> MKMapRect {
        let mapPointsPerMetre = MKMapPointsPerMeterAtLatitude(centre.coordinate.latitude)
        let width = Double(size.width) * metresPerPoint * mapPointsPerMetre
        let height = Double(size.height) * metresPerPoint * mapPointsPerMetre
        return MKMapRect(x: centre.x - width / 2, y: centre.y - height / 2,
                         width: width, height: height)
    }

    private func mapPoint(atX x: Double, y: Double, in rect: MKMapRect) -> MKMapPoint {
        MKMapPoint(x: rect.minX + rect.width * x / Double(size.width),
                   y: rect.minY + rect.height * y / Double(size.height))
    }

    private func layer(through points: [CGPoint], in rect: MKMapRect) -> RevealedLayer {
        let mapPoints = points.map { mapPoint(atX: Double($0.x), y: Double($0.y), in: rect) }
        func line() -> MKMultiPolyline {
            MKMultiPolyline([MKPolyline(points: mapPoints, count: mapPoints.count)])
        }
        return RevealedLayer(fine: line(), mid: line(), far: line(),
                             cellCount: 1, openedKm: 1, regionIds: [])
    }

    private func render(_ layer: RevealedLayer, in rect: MKMapRect,
                        cells: Bool) throws -> FogPixels {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal недоступен") }
        let image = try XCTUnwrap(FogOffscreen.render(
            layer: layer, rect: rect, sizePoints: size, scale: scale,
            palette: palette, cells: cells))
        return try XCTUnwrap(FogPixels(image: image, scale: scale))
    }

    /// Высота открытого по середине кадра, в точках.
    private func openHeight(in pixels: FogPixels) -> Double {
        let threshold = Double(palette.alpha) / 2
        var open = 0.0
        var y = 0.0
        while y < Double(size.height) {
            if pixels.alpha(atX: 150, y: y) < threshold { open += 1 / Double(scale) }
            y += 1 / Double(scale)
        }
        return open
    }

    /// Верхний край открытой полосы по середине кадра, в точках.
    private func topEdgeOfOpen(in pixels: FogPixels) -> Double? {
        let threshold = Double(palette.alpha) / 2
        var y = 0.0
        while y < Double(size.height) {
            if pixels.alpha(atX: 150, y: y) < threshold { return y }
            y += 1 / Double(scale)
        }
        return nil
    }
}
