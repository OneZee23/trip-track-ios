import XCTest
import CoreLocation
@testable import TripTrack

/// Фотографии на маршруте.
///
/// Просьба из машины: «чтобы при отображении на карте отображались фотографии
/// по поездке по таймлайну». Порядок источников важнее самой расстановки:
/// координата из снимка, иначе — время съёмки и трек, иначе — ничего.
///
/// Последнее не недоделка, а решение. У снимков до 0.6.5 сохранялось только
/// время ПОПАДАНИЯ в базу, которое может отличаться от съёмки на дни: поставить
/// кадр по нему — увезти его за сотню километров от места, где он снят.
final class TripPhotoPlacementTests: XCTestCase {

    private static let metersPerDegree = 111_320.0
    private let start = Date(timeIntervalSince1970: 1_780_000_000)

    private func track(seconds: Int) -> [TrackPoint] {
        (0...seconds).map { t in
            TrackPoint(
                latitude: 45.0 + Double(t) * 10 / Self.metersPerDegree,
                longitude: 38.9, speed: 10,
                timestamp: start.addingTimeInterval(Double(t)))
        }
    }

    private func photo(capturedAt: Date?, lat: Double? = nil, lon: Double? = nil) -> TripPhoto {
        TripPhoto(id: UUID(), filename: "p.jpg", caption: nil,
                  timestamp: start, capturedAt: capturedAt,
                  exifLatitude: lat, exifLongitude: lon)
    }

    /// Координата в снимке — правда о том, где стояла камера. Её и берём, даже
    /// когда трек мог бы предложить своё место.
    func testThePhotoOwnCoordinateWins() {
        let placed = TripPhotoPlacement.place(
            [photo(capturedAt: start.addingTimeInterval(50), lat: 44.0, lon: 37.0)],
            on: track(seconds: 100))

        XCTAssertEqual(placed.count, 1)
        XCTAssertEqual(placed.first?.source, .photo)
        XCTAssertEqual(placed.first?.latitude ?? 0, 44.0, accuracy: 0.0001)
    }

    /// Геометки выключены — считаем по треку. Ради этого случая и делалась
    /// точность 0.6.5: на прежних точках ответ был бы «где-то в этом квартале».
    func testWithoutACoordinateThePlaceComesFromTheTrack() {
        let placed = TripPhotoPlacement.place(
            [photo(capturedAt: start.addingTimeInterval(50))],
            on: track(seconds: 100))

        XCTAssertEqual(placed.first?.source, .track)
        // 50 секунд по 10 м/с — пятьсот метров от старта.
        let expected = 45.0 + 500 / Self.metersPerDegree
        XCTAssertEqual(placed.first?.latitude ?? 0, expected, accuracy: 0.0002)
    }

    /// Снимок без времени съёмки на карту не встаёт. Это про все фотографии,
    /// добавленные до 0.6.5, — и молчание тут честнее догадки.
    func testAPhotoWithoutACaptureTimeStaysOffTheMap() {
        XCTAssertTrue(
            TripPhotoPlacement.place([photo(capturedAt: nil)], on: track(seconds: 100)).isEmpty)
    }

    /// Снятое до выезда или назавтра к маршруту не относится.
    func testAPhotoTakenOutsideTheTripStaysOffTheMap() {
        let before = photo(capturedAt: start.addingTimeInterval(-3_600))
        let after = photo(capturedAt: start.addingTimeInterval(86_400))
        XCTAssertTrue(TripPhotoPlacement.place([before, after], on: track(seconds: 100)).isEmpty)
    }

    /// Поездка без трека (пришла из ленты превью-полилинией) ничего не
    /// расставляет — но и не падает.
    func testATripWithoutATrackPlacesNothing() {
        XCTAssertTrue(
            TripPhotoPlacement.place([photo(capturedAt: start)], on: []).isEmpty)
    }
}
