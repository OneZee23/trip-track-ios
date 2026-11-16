import XCTest
import CoreLocation
@testable import TripTrack

final class FilmingModeFiltersTests: XCTestCase {
    func testPlaceInsideHiddenRunIsFiltered() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = (0..<9).map { index in
            TrackPoint(latitude: 45 + Double(index) * 0.002, longitude: 39,
                       speed: 9, timestamp: start.addingTimeInterval(Double(index) * 60))
        }
        let trip = Trip(
            startDate: start,
            trackPoints: points,
            hiddenParts: TripHiddenParts(sections: [HiddenSection(
                id: UUID(), from: points[3].timestamp, to: points[5].timestamp
            )])
        )

        XCTAssertTrue(FilmingModeFilters.hidesPlace(points[4].coordinate,
            trips: [trip], homeZone: nil, defaultEdgeMetres: nil))
        XCTAssertFalse(FilmingModeFilters.hidesPlace(points[1].coordinate,
            trips: [trip], homeZone: nil, defaultEdgeMetres: nil))
    }

    func testPlaceInsideHomeZoneIsFiltered() {
        let home = CLLocationCoordinate2D(latitude: 45, longitude: 39)
        let zone: Zone = (centre: home, radius: 250)
        XCTAssertTrue(FilmingModeFilters.hidesPlace(home, trips: [], homeZone: zone,
            defaultEdgeMetres: nil))
        XCTAssertFalse(FilmingModeFilters.hidesPlace(
            CLLocationCoordinate2D(latitude: 45.01, longitude: 39), trips: [],
            homeZone: zone, defaultEdgeMetres: nil))
    }

    func testAtlasPreviewLayerAndNumbersUseMaskedPublicPreview() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = (0..<21).map { index in
            TrackPoint(latitude: 45 + Double(index) * 0.001, longitude: 39,
                       speed: 10, timestamp: start.addingTimeInterval(Double(index) * 30))
        }
        let full = AtlasPreviewLayer.build(trips: [previewTrip(points)], atlas: nil)
        let mask = HiddenPartsResolver.resolve(
            points: points, recordingBreaks: [], startMetres: 0, endMetres: 0,
            sections: [HiddenSection(id: UUID(), from: points[8].timestamp,
                                     to: points[12].timestamp)])
        var publicTrip = previewTrip(mask.visiblePoints)
        publicTrip.previewBreaks = mask.previewBreaks
        let filming = AtlasPreviewLayer.build(trips: [publicTrip], atlas: nil)

        XCTAssertGreaterThan(full.openedKm, filming.openedKm)
        XCTAssertFalse(filming.isEmpty)
        XCTAssertEqual(AtlasPreviewLayer.previewRuns(publicTrip).count, 2)

        let hiddenPhoto = TripPhoto(
            id: UUID(), filename: "hidden.jpg", caption: nil,
            timestamp: start, capturedAt: points[10].timestamp,
            exifLatitude: points[10].latitude, exifLongitude: points[10].longitude)
        let visiblePhoto = TripPhoto(
            id: UUID(), filename: "visible.jpg", caption: nil,
            timestamp: start, capturedAt: points[2].timestamp,
            exifLatitude: points[2].latitude, exifLongitude: points[2].longitude)
        XCTAssertEqual(FilmingModeFilters.visiblePhotos(
            [hiddenPhoto, visiblePhoto], points: points, resolution: mask,
            homeZone: nil).map(\.filename), ["visible.jpg"])
    }

    func testLocationDotIsHiddenExceptOnRecordingScreen() {
        XCTAssertFalse(FilmingModeFilters.keepsLocationDot(isFilming: true,
            isRecordingScreen: false))
        XCTAssertTrue(FilmingModeFilters.keepsLocationDot(isFilming: true,
            isRecordingScreen: true))
        XCTAssertTrue(FilmingModeFilters.keepsLocationDot(isFilming: false,
            isRecordingScreen: false))
    }

    private func previewTrip(_ points: [TrackPoint]) -> Trip {
        var trip = Trip(startDate: points.first?.timestamp ?? .distantPast)
        trip.previewPolyline = Trip.encodePolyline(points.map(\.coordinate))
        return trip
    }
}
