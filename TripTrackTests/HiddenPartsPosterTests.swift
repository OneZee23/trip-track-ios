import CoreLocation
import XCTest
@testable import TripTrack

final class HiddenPartsPosterTests: XCTestCase {
    func testOwnPosterUsesPublicRouteNumbersAndVisiblePhotos() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = (0...30).map { index in
            TrackPoint(latitude: 40, longitude: Double(index) * 0.0001,
                       speed: 10, timestamp: start.addingTimeInterval(Double(index) * 60))
        }
        let hiddenPhoto = TripPhoto(
            id: UUID(), filename: "hidden.jpg", caption: nil,
            timestamp: start, capturedAt: points[15].timestamp)
        let visiblePhoto = TripPhoto(
            id: UUID(), filename: "visible.jpg", caption: nil,
            timestamp: start, capturedAt: points[2].timestamp)
        let trip = Trip(
            startDate: start, endDate: points.last?.timestamp, distance: 3_000,
            maxSpeed: 25, averageSpeed: 10, trackPoints: points,
            photos: [hiddenPhoto, visiblePhoto],
            hiddenParts: TripHiddenParts(
                startMetres: 0, endMetres: 0,
                sections: [HiddenSection(id: UUID(), from: points[10].timestamp, to: points[20].timestamp)],
                numbersVisibleOnly: true),
            title: "Trip", fuelUsed: 0, elevation: 0, region: nil,
            isPrivate: false, earnedBadgeIds: [])

        let data = StoryShareData.from(
            trip, authorName: "A", authorEmoji: "🚗", unit: .km, lang: .en)

        XCTAssertEqual(data.coordinates.count, 20)
        XCTAssertEqual(data.breaks, [10])
        XCTAssertEqual(data.photoSource, .local(filename: "visible.jpg"))
        XCTAssertEqual(data.distance.value, "0.2")
    }
}
