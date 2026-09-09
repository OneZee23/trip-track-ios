import XCTest
import CoreLocation
@testable import TripTrack

/// Лента «Моменты»: отметки и стопки снимков по порядку дороги.
final class TripMomentsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func checkpoint(at seconds: TimeInterval) -> TripCheckpoint {
        TripCheckpoint(timestamp: start.addingTimeInterval(seconds), latitude: 45, longitude: 38.9,
                       distanceFromStart: seconds * 10, elapsedFromStart: seconds)
    }

    private func placed(at seconds: TimeInterval) -> TripMoments.PlacedPhoto {
        let photo = TripPhoto(id: UUID(), filename: "x.jpg", caption: nil, timestamp: start)
        let fix = TripRouteLocator.Fix(index: 0, coordinate: CLLocationCoordinate2D(latitude: 45, longitude: 38.9),
                                       timestamp: start.addingTimeInterval(seconds),
                                       distanceFromStart: seconds * 10, elapsedFromStart: seconds)
        return TripMoments.PlacedPhoto(photo: photo, fix: fix)
    }

    /// Номера отметок — по времени, а не по порядку постановки: отметка,
    /// поставленная задним числом в начале дороги, становится первой.
    func testCheckpointsAreNumberedByTimeNotByInsertion() {
        let late = checkpoint(at: 3_600)
        let early = checkpoint(at: 600)
        let moments = TripMoments.build(checkpoints: [late, early], links: [:], loose: [])
        guard case .checkpoint(let first, let number, _) = moments[0] else { return XCTFail() }
        XCTAssertEqual(first.id, early.id)
        XCTAssertEqual(number, 1)
    }

    /// Кадры в пределах четверти часа — одна стопка; дальше — новая.
    func testLoosePhotosAreStackedByTheLinkingWindow() {
        let loose = [placed(at: 100), placed(at: 500), placed(at: 100 + 16 * 60)]
        let moments = TripMoments.build(checkpoints: [], links: [:], loose: loose)
        XCTAssertEqual(moments.count, 2)
        guard case .photos(_, let photos) = moments[0] else { return XCTFail() }
        XCTAssertEqual(photos.count, 2)
    }

    /// Стопка снимков и отметка встают в ленту по времени вперемешку.
    func testMomentsInterleaveByTime() {
        let moments = TripMoments.build(
            checkpoints: [checkpoint(at: 2_000)], links: [:],
            loose: [placed(at: 500), placed(at: 4_000)])
        XCTAssertEqual(moments.map(\.elapsedFromStart), [500, 2_000, 4_000])
    }

    /// Снимки отметки идут с ней, а не отдельной стопкой.
    func testLinkedPhotosRideWithTheirCheckpoint() {
        let cp = checkpoint(at: 1_000)
        let photo = TripPhoto(id: UUID(), filename: "y.jpg", caption: nil, timestamp: start)
        let moments = TripMoments.build(checkpoints: [cp], links: [cp.id: [photo]], loose: [])
        XCTAssertEqual(moments.count, 1)
        guard case .checkpoint(_, _, let photos) = moments[0] else { return XCTFail() }
        XCTAssertEqual(photos.map(\.id), [photo.id])
    }
}
