import XCTest
import CoreLocation
@testable import TripTrack

/// Секрет закрыт: в бандле только хеши. Значит проверять можно ровно две
/// вещи — что совпадение хеша находит нужную ячейку и что `reach` не пускает
/// того, кто в ней не был.
final class SecretMatcherTests: XCTestCase {

    private let salt = "tt-secrets-v1"
    /// Гумбаши: горная дорога, широта та же, на какой считались размеры
    /// ячейки в комментариях.
    private let anchor = CLLocationCoordinate2D(latitude: 43.6234, longitude: 41.4571)

    private var cell: String {
        GeohashEncoder.encode(latitude: anchor.latitude, longitude: anchor.longitude, precision: 7)
    }

    private var centre: CLLocationCoordinate2D {
        GeohashEncoder.centerCoordinate(of: cell)
    }

    private func record(
        id: String = "komsomolsky",
        cells: [String]? = nil,
        reach: Double = 300,
        polygon: Bool = false,
        symbol: SealSymbol = .pass
    ) -> SecretRecord {
        let hashed = (cells ?? [cell]).map { SecretHash.truncated(salt: salt, geohash7: $0) }
        return SecretRecord(id: id, hashes: hashed, reach: reach, symbol: symbol, polygon: polygon)
    }

    // MARK: - Ячейка и reach

    func testTrackThroughTheCellFindsTheSecret() {
        let track = DiscoveryTrackFixtures.line(
            from: DiscoveryTrackFixtures.offset(centre, eastMetres: -300),
            to: DiscoveryTrackFixtures.offset(centre, eastMetres: 300))

        let matches = SecretMatcher.matches(track: track, catalog: [record()], salt: salt)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.secretId, "komsomolsky")
        XCTAssertEqual(matches.first?.symbol, .pass)
        // Координата — центр ячейки: другой у нас нет и быть не может.
        XCTAssertEqual(matches.first?.coordinate.latitude ?? 0, centre.latitude, accuracy: 1e-9)
        XCTAssertEqual(matches.first?.coordinate.longitude ?? 0, centre.longitude, accuracy: 1e-9)
    }

    /// Четыреста метров мимо — это уже не соседняя ячейка, и хеш не совпадает
    /// вовсе.
    func testTrackFourHundredMetresAwayFindsNothing() {
        let far = DiscoveryTrackFixtures.offset(centre, northMetres: 400)
        let track = DiscoveryTrackFixtures.line(
            from: DiscoveryTrackFixtures.offset(far, eastMetres: -200),
            to: DiscoveryTrackFixtures.offset(far, eastMetres: 200))

        XCTAssertTrue(SecretMatcher.matches(track: track, catalog: [record()], salt: salt).isEmpty)
    }

    /// А вот здесь `reach` работает один, без помощи геохеша: трек идёт по
    /// СОСЕДНЕЙ ячейке в двухстах метрах от центра. Хеш совпадает в обоих
    /// случаях, различает их только радиус.
    func testNeighbourCellCountsOnlyWithinReach() {
        let near = DiscoveryTrackFixtures.offset(centre, northMetres: 200)
        let track = DiscoveryTrackFixtures.line(
            from: DiscoveryTrackFixtures.offset(near, eastMetres: -30),
            to: DiscoveryTrackFixtures.offset(near, eastMetres: 30))

        XCTAssertEqual(
            SecretMatcher.matches(track: track, catalog: [record(reach: 300)], salt: salt).count, 1,
            "двести метров — это внутри трёхсот")
        XCTAssertTrue(
            SecretMatcher.matches(track: track, catalog: [record(reach: 150)], salt: salt).isEmpty,
            "и снаружи ста пятидесяти")
    }

    // MARK: - Полигон

    func testPolygonSecretIgnoresReach() {
        // Трек идёт по самой ячейке секрета, но в сорока метрах от её центра.
        let line = DiscoveryTrackFixtures.offset(centre, northMetres: 40)
        let track = DiscoveryTrackFixtures.line(
            from: DiscoveryTrackFixtures.offset(line, eastMetres: -20),
            to: DiscoveryTrackFixtures.offset(line, eastMetres: 20))

        XCTAssertEqual(
            SecretMatcher.matches(track: track, catalog: [record(reach: 10, polygon: true)], salt: salt).count, 1)
        XCTAssertTrue(
            SecretMatcher.matches(track: track, catalog: [record(reach: 10, polygon: false)], salt: salt).isEmpty,
            "точечному секрету десяти метров не хватает — в этом и разница")
    }

    /// Соседей полигону не выдаём: они раздули бы его на полторы сотни метров
    /// во все стороны.
    func testPolygonDoesNotBorrowNeighbourCells() {
        let track = DiscoveryTrackFixtures.line(
            from: DiscoveryTrackFixtures.offset(centre, eastMetres: -20),
            to: DiscoveryTrackFixtures.offset(centre, eastMetres: 20))
        let neighbour = GeohashEncoder.neighbors(of: cell)[0]

        XCTAssertTrue(SecretMatcher.matches(
            track: track, catalog: [record(cells: [neighbour], polygon: true)], salt: salt).isEmpty)
        XCTAssertEqual(SecretMatcher.matches(
            track: track, catalog: [record(cells: [neighbour], polygon: false)], salt: salt).count, 1,
            "точечный секрет в соседней ячейке в пределах reach — находится")
    }

    // MARK: - Соль и вырожденное

    func testWrongSaltFindsNothing() {
        let track = DiscoveryTrackFixtures.line(
            from: DiscoveryTrackFixtures.offset(centre, eastMetres: -100),
            to: DiscoveryTrackFixtures.offset(centre, eastMetres: 100))

        XCTAssertTrue(SecretMatcher.matches(track: track, catalog: [record()], salt: "tt-secrets-v2").isEmpty)
    }

    func testEmptyInputsAreSilent() {
        XCTAssertTrue(SecretMatcher.matches(track: [], catalog: [record()], salt: salt).isEmpty)
        XCTAssertTrue(SecretMatcher.matches(
            track: DiscoveryTrackFixtures.line(from: anchor, to: DiscoveryTrackFixtures.offset(anchor, eastMetres: 50)),
            catalog: [], salt: salt).isEmpty)
    }

    /// Секрет с несколькими ячейками всё равно даёт ОДНУ печать.
    func testSecretWithManyCellsMatchesOnce() {
        let track = DiscoveryTrackFixtures.line(
            from: DiscoveryTrackFixtures.offset(centre, eastMetres: -300),
            to: DiscoveryTrackFixtures.offset(centre, eastMetres: 300))
        let cells = [cell] + GeohashEncoder.neighbors(of: cell)

        XCTAssertEqual(SecretMatcher.matches(track: track, catalog: [record(cells: cells)], salt: salt).count, 1)
    }

    // MARK: - Ячейки трека

    func testTrackCellsPrecision() {
        let track = DiscoveryTrackFixtures.line(
            from: anchor, to: DiscoveryTrackFixtures.offset(anchor, eastMetres: 600))
        let fine = TrackCells.geohash7(track)
        let coarse = TrackCells.geohash5(track)

        XCTAssertFalse(fine.isEmpty)
        XCTAssertTrue(fine.allSatisfy { $0.count == 7 })
        XCTAssertTrue(coarse.allSatisfy { $0.count == 5 })
        XCTAssertGreaterThan(fine.count, coarse.count, "шестьсот метров — это несколько ячеек по 150 м и одна по 5 км")
        XCTAssertTrue(coarse.isSubset(of: Set(fine.map { String($0.prefix(5)) })))
    }
}
