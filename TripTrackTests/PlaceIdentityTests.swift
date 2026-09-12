import XCTest
@testable import TripTrack

/// Место — ячейка geohash-7, а его id — функция от ячейки. Это контракт между
/// телефонами: места не синхронизируются, и два устройства, независимо
/// пересчитав историю, обязаны дать один и тот же id. Векторы заморожены:
/// поменяется пространство имён или алгоритм — упадёт этот тест, а не
/// разъедутся отметки на двух телефонах.
final class PlaceIdentityTests: XCTestCase {

    func testCellIsGeohash7() {
        // Джубга, поворот к морю.
        XCTAssertEqual(Place.cell(latitude: 44.3196, longitude: 38.7089), "szgs0u4")
        // 60 м севернее — тот же двор, та же ячейка.
        XCTAssertEqual(Place.cell(latitude: 44.3201, longitude: 38.7089), "szgs0u4")
        // 400 м севернее — уже другое место.
        XCTAssertEqual(Place.cell(latitude: 44.3232, longitude: 38.7089), "szgs0uf")
    }

    func testIdIsDeterministicUUIDv5() {
        XCTAssertEqual(Place.id(forCell: "u4pruyd").uuidString, "2D124877-5BCA-5830-B12E-A09F8176B7D9")
        XCTAssertEqual(Place.id(forCell: "v0b3xg2").uuidString, "5900AC91-1D76-5169-9437-EA51B6D37507")
        XCTAssertEqual(Place.id(forCell: "u4pruyd"), Place.id(forCell: "u4pruyd"))
        XCTAssertNotEqual(Place.id(forCell: "u4pruyd"), Place.id(forCell: "u4pruye"))
    }

    /// Версия 5 и вариант RFC 4122 — по битам, а не по вере: сторонний
    /// разбор id (сервер хранит его как непрозрачную строку) обязан видеть
    /// валидный UUID.
    func testIdCarriesVersionAndVariantBits() {
        let bytes = withUnsafeBytes(of: Place.id(forCell: "u4pruyd").uuid) { Array($0) }
        XCTAssertEqual(bytes[6] >> 4, 5)
        XCTAssertEqual(bytes[8] >> 6, 0b10)
    }

    func testPassKnowsWhetherItHasACourse() {
        let known = PlacePass(placeId: UUID(), tripId: UUID(), timestamp: Date(),
                              elapsedFromStart: 1, distanceFromStart: 1, course: 271)
        let unknown = PlacePass(placeId: UUID(), tripId: UUID(), timestamp: Date(),
                                elapsedFromStart: 1, distanceFromStart: 1, course: PlacePass.unknownCourse)
        XCTAssertTrue(known.hasCourse)
        XCTAssertFalse(unknown.hasCourse)
    }
}
