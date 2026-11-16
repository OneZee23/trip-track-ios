import CoreLocation
import XCTest
@testable import TripTrack

final class MapSnapshotContentCacheTests: XCTestCase {
    func testCacheKeyChangesWhenRouteGeometryChanges() {
        let original = [
            CLLocationCoordinate2D(latitude: 10, longitude: 20),
            CLLocationCoordinate2D(latitude: 11, longitude: 21),
            CLLocationCoordinate2D(latitude: 12, longitude: 22)
        ]
        let edited = [
            original[0],
            CLLocationCoordinate2D(latitude: 11.5, longitude: 21),
            original[2]
        ]

        XCTAssertNotEqual(MapSnapshotPreview.contentKey(original), MapSnapshotPreview.contentKey(edited))
    }
}
