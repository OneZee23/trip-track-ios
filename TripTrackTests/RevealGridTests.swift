import XCTest
import CoreLocation
@testable import TripTrack

/// Сетка открытого мира — чистая арифметика, и проверять её надо до того, как
/// на ней вырастет рендерер: ошибка в ячейке видна не цифрой в тесте, а
/// коридором, съехавшим на квартал, — через месяц и на устройстве.
final class RevealGridTests: XCTestCase {
    private let krasnodar = CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9753)

    /// Координата ровно в центре своей ячейки — чтобы «30 м в сторону» не
    /// оказались случайно по разные стороны границы.
    private func cellCentre(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        RevealGrid.center(of: RevealGrid.cell(for: c), in: RevealGrid.tileKey(for: c))
    }

    private func offset(
        _ c: CLLocationCoordinate2D, north: Double = 0, east: Double = 0
    ) -> CLLocationCoordinate2D {
        let dLat = north / 111_320.0
        let dLon = east / (111_320.0 * cos(c.latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: c.latitude + dLat, longitude: c.longitude + dLon)
    }

    // MARK: - Ячейка

    func testCellIsStableForOneCoordinate() {
        let first = RevealGrid.cell(for: krasnodar)
        for _ in 0..<10 {
            XCTAssertEqual(RevealGrid.cell(for: krasnodar), first)
        }
    }

    func testThirtyMetresStaysInTheSameCell() {
        let centre = cellCentre(krasnodar)
        let cell = RevealGrid.cell(for: centre)
        XCTAssertEqual(RevealGrid.cell(for: offset(centre, north: 30)), cell)
        XCTAssertEqual(RevealGrid.cell(for: offset(centre, north: -30)), cell)
        XCTAssertEqual(RevealGrid.cell(for: offset(centre, east: 30)), cell)
        XCTAssertEqual(RevealGrid.cell(for: offset(centre, east: -30)), cell)
    }

    func testHundredAndTwentyMetresIsAnotherCell() {
        let centre = cellCentre(krasnodar)
        let cell = RevealGrid.cell(for: centre)
        XCTAssertNotEqual(RevealGrid.cell(for: offset(centre, north: 120)), cell)
        XCTAssertNotEqual(RevealGrid.cell(for: offset(centre, east: 120)), cell)
    }

    /// Ячейка обязана быть квадратной: иначе «75 м» на широте Мурманска
    /// означало бы 75 м по вертикали и 150 по горизонтали.
    func testCellIsNearSquareFarNorth() {
        let murmansk = CLLocationCoordinate2D(latitude: 68.97, longitude: 33.07)
        let tile = RevealGrid.tileIndex(for: murmansk)
        let lonStep = RevealGrid.lonDegrees(inTile: tile)
        let metresPerLon = 111_320.0 * cos(murmansk.latitude * .pi / 180)
        let width = lonStep * metresPerLon
        let height = RevealGrid.cellDegrees * 111_320.0
        XCTAssertEqual(width, height, accuracy: 4, "ячейка должна оставаться квадратной")
    }

    /// Арифметика тайла обязана сходиться с настоящим geohash-5: по строке
    /// ячейки читаются обратно, по числам — считаются.
    func testTileArithmeticMatchesGeohash() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let lat = Double.random(in: -80...80, using: &generator)
            let lon = Double.random(in: -179...179, using: &generator)
            let c = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            XCTAssertEqual(RevealGrid.tileKey(RevealGrid.tileIndex(for: c)), RevealGrid.tileKey(for: c))
        }
    }

    // MARK: - Код

    func testEncodeDecodeRoundTripEmpty() {
        let tile = RevealGrid.tileKey(for: krasnodar)
        let data = RevealGrid.encode([], in: tile)
        XCTAssertTrue(data.isEmpty)
        XCTAssertEqual(RevealGrid.decode(data, in: tile), [])
    }

    func testEncodeDecodeRoundTripOneCell() {
        let tile = RevealGrid.tileKey(for: krasnodar)
        let cell = RevealGrid.cell(for: krasnodar)
        let back = RevealGrid.decode(RevealGrid.encode([cell], in: tile), in: tile)
        XCTAssertEqual(back, [cell])
    }

    func testEncodeDecodeRoundTripWholeTile() {
        let tile = RevealGrid.tileKey(for: krasnodar)
        let origin = RevealGrid.tileOrigin(tile)
        var cells: [RevealGrid.Cell] = []
        for row in 0..<64 {
            for col in 0..<63 {
                cells.append(RevealGrid.Cell(row: origin.row0 + Int32(row), col: origin.col0 + Int32(col)))
            }
        }
        XCTAssertEqual(cells.count, 4_032)

        let data = RevealGrid.encode(cells, in: tile)
        XCTAssertEqual(Set(RevealGrid.decode(data, in: tile)), Set(cells))
    }

    /// Плотный ряд — это и есть открытая дорога: дельта 1, значит байт на
    /// ячейку. Если код вдруг станет дороже двух байт, на телефоне с большой
    /// библиотекой это сотни килобайт на пустом месте.
    func testDenseRowCostsAtMostTwoBytesPerCell() {
        let tile = RevealGrid.tileKey(for: krasnodar)
        let origin = RevealGrid.tileOrigin(tile)
        let cells = (0..<64).map { RevealGrid.Cell(row: origin.row0 + 7, col: origin.col0 + Int32($0)) }
        let data = RevealGrid.encode(cells, in: tile)
        XCTAssertLessThanOrEqual(Double(data.count) / Double(cells.count), 2.0)
    }

    /// Ячейка чужого тайла не имеет локального индекса — и записать её вместо
    /// своей значило бы вернуть при чтении кусок дороги в другом месте.
    func testForeignCellIsDropped() {
        let tile = RevealGrid.tileKey(for: krasnodar)
        let origin = RevealGrid.tileOrigin(tile)
        let foreign = RevealGrid.Cell(row: origin.row0 + 5_000, col: origin.col0)
        let data = RevealGrid.encode([foreign], in: tile)
        XCTAssertTrue(data.isEmpty)
    }

    // MARK: - Ход по линии

    func testWalkAlongOneKilometreOpensFourteenCellsWithoutGaps() {
        let start = cellCentre(krasnodar)
        let end = offset(start, north: 1_000)
        var cells: [RevealGrid.Cell] = []
        RevealGrid.walkCells([start, end]) { cell, _ in cells.append(cell) }

        let rows = cells.map(\.row)
        let unique = Set(rows).sorted()
        XCTAssertGreaterThanOrEqual(unique.count, 13)
        XCTAssertLessThanOrEqual(unique.count, 15)
        for i in 1..<unique.count {
            XCTAssertEqual(unique[i] - unique[i - 1], 1, "ряды обязаны идти подряд")
        }
        // Один километр по меридиану пересекает границу тайла geohash-5, а шаг
        // ячейки по долготе считается от косинуса широты ЦЕНТРА тайла — значит
        // на стыке столбец меняется, и один ряд отдаёт две ячейки. Это цена
        // квадратной ячейки, и она в одну ячейку на 4.9 км: сетка живёт внутри
        // своего тайла, сравнивать `Cell` из разных тайлов нельзя.
        XCTAssertLessThanOrEqual(cells.count, unique.count + 1)
        XCTAssertLessThanOrEqual(Set(cells.map(\.col)).count, 2)
    }

    /// Диагональ — та же проверка, но по обеим осям: шаг в треть ячейки
    /// существует ровно затем, чтобы ход не перепрыгивал через ячейку.
    func testWalkDoesNotSkipCellsOnADiagonal() {
        let start = cellCentre(krasnodar)
        let end = offset(start, north: 700, east: 700)
        var cells: [RevealGrid.Cell] = []
        RevealGrid.walkCells([start, end]) { cell, _ in cells.append(cell) }

        for i in 1..<cells.count {
            let dr = abs(cells[i].row - cells[i - 1].row)
            let dc = abs(cells[i].col - cells[i - 1].col)
            XCTAssertLessThanOrEqual(max(dr, dc), 1, "ход не имеет права перешагнуть ячейку")
            XCTAssertGreaterThan(dr + dc, 0)
        }
        XCTAssertGreaterThan(cells.count, 9)
    }

    /// Разрыв записи — не дорога. Прыжок через полстраны не должен прочертить
    /// коридор по прямой.
    func testWalkSkipsATeleport() {
        let a = krasnodar
        let b = CLLocationCoordinate2D(latitude: 55.75, longitude: 37.62)
        var count = 0
        RevealGrid.walkCells([a, b]) { _, _ in count += 1 }
        XCTAssertEqual(count, 0)
    }
}
