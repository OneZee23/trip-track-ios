import XCTest
@testable import TripTrack

/// Карточка снимка под булавкой карты.
///
/// Жалоба владельца на устройстве: тап по фото на полноэкранной карте
/// открывался «слишком тяжело» — сначала выезжал полный экран, потом
/// разворачивалась картинка. Между булавкой и просмотрщиком встала карточка,
/// и всё, что она печатает, считается вне `body`: стопка соседних булавок —
/// это проход по всем снимкам поездки.
final class MapPhotoPreviewTests: XCTestCase {

    private func pin(_ id: UUID, lat: Double, lon: Double,
                     reading: String? = nil, filename: String? = nil) -> PhotoPin {
        PhotoPin(id: id, latitude: lat, longitude: lon, image: nil,
                 accessibilityLabel: "", reading: reading, filename: filename)
    }

    func testLonePinCarriesItsReadingAndFile() {
        let id = UUID()
        let pins = [pin(id, lat: 45.0, lon: 39.0, reading: "1 ч 19 мин · 106 км",
                        filename: "trip/a.jpg")]
        let preview = MapPhotoPreview.build(photoId: id, pins: pins)
        XCTAssertEqual(preview?.index, 1)
        XCTAssertEqual(preview?.total, 1)
        XCTAssertEqual(preview?.reading, "1 ч 19 мин · 106 км")
        XCTAssertEqual(preview?.filename, "trip/a.jpg")
    }

    /// «1 из 1» — не ответ, а шум.
    func testCounterIsSilentForASinglePhoto() {
        let id = UUID()
        let preview = MapPhotoPreview.build(photoId: id, pins: [pin(id, lat: 45, lon: 39)])
        XCTAssertNil(preview?.counterText(.ru))
    }

    /// Стопка — это то, что палец накрывает целиком: три кадра с одной
    /// смотровой площадки. Снимки с разных концов маршрута ей не считаются.
    func testStackCountsOnlyNeighbours() {
        let a = UUID(), b = UUID(), far = UUID()
        let pins = [
            pin(a, lat: 45.0000, lon: 39.0000),
            pin(b, lat: 45.0002, lon: 39.0000),      // ~22 м
            pin(far, lat: 45.0500, lon: 39.0000)     // ~5.5 км
        ]
        let first = MapPhotoPreview.build(photoId: a, pins: pins)
        XCTAssertEqual(first?.total, 2)
        XCTAssertEqual(first?.index, 1)
        XCTAssertEqual(first?.counterText(.ru), "1 из 2")

        let second = MapPhotoPreview.build(photoId: b, pins: pins)
        XCTAssertEqual(second?.index, 2)
        XCTAssertEqual(second?.counterText(.en), "2 of 2")

        let alone = MapPhotoPreview.build(photoId: far, pins: pins)
        XCTAssertEqual(alone?.total, 1)
        XCTAssertNil(alone?.counterText(.ru))
    }

    /// «Сколько до сюда» есть не у всякого кадра: снимок без координаты и
    /// без времени съёмки на трек не встаёт, и врать ему нечем.
    func testUnplacedPhotoHasNoReading() {
        let id = UUID()
        let preview = MapPhotoPreview.build(photoId: id, pins: [pin(id, lat: 45, lon: 39)])
        XCTAssertNil(preview?.reading)
    }

    func testUnknownPhotoBuildsNothing() {
        let pins = [pin(UUID(), lat: 45, lon: 39)]
        XCTAssertNil(MapPhotoPreview.build(photoId: UUID(), pins: pins))
    }

    /// «из» — предлог, и на тринадцати языках это не всегда «X of Y».
    func testCounterGoesThroughTheLocalisedPreposition() {
        let a = UUID(), b = UUID()
        let pins = [pin(a, lat: 45, lon: 39), pin(b, lat: 45.0001, lon: 39)]
        let preview = MapPhotoPreview.build(photoId: b, pins: pins)
        XCTAssertEqual(preview?.counterText(.de), "2 von 2")
        XCTAssertEqual(preview?.counterText(.tr), "2 taneden 2")
    }
}
