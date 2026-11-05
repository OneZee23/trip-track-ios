import CoreData
import XCTest
@testable import TripTrack

final class HiddenPartsPullPersistenceTests: XCTestCase {
    func testLegacyPullKeepsLocalFullTripAndHiddenPhoto() throws {
        let pc = PersistenceController(inMemory: true)
        let repo = CoreDataTripRepository(persistenceController: pc)
        let context = pc.container.viewContext
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let id = UUID()
        let localPoints = (0..<10).map { index in
            TrackPoint(latitude: 40, longitude: Double(index) * 0.01,
                       altitude: Double(index) * 50, speed: 10,
                       timestamp: start.addingTimeInterval(Double(index) * 60))
        }
        let local = TripEntity(context: context)
        local.id = id
        local.startDate = start
        local.endDate = localPoints.last?.timestamp
        local.distance = 10_000
        local.maxSpeed = 30
        local.averageSpeed = 12
        local.fuelUsed = 4
        local.elevation = 450
        local.syncStatus = SyncStatus.synced.rawValue
        let hiddenParts = TripHiddenParts(
            sections: [HiddenSection(id: UUID(), from: localPoints[4].timestamp,
                                     to: localPoints[6].timestamp)],
            numbersVisibleOnly: false)
        local.setValue(String(data: try JSONEncoder().encode(hiddenParts), encoding: .utf8),
                        forKey: "hiddenPartsJSON")
        for point in localPoints {
            let entity = TrackPointEntity(context: context)
            entity.id = point.id
            entity.latitude = point.latitude
            entity.longitude = point.longitude
            entity.altitude = point.altitude
            entity.speed = point.speed
            entity.timestamp = point.timestamp
            entity.trip = local
        }
        let localPreview = Trip.encodePolyline(localPoints.map(\.coordinate))
        local.previewPolyline = localPreview

        let imageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([0x01, 0x02]).write(to: imageURL)
        defer {
            try? FileManager.default.removeItem(at: imageURL)
            context.reset()
        }
        let visiblePoints = Array(localPoints[0...3]) + Array(localPoints[7...9])
        let remoteTrip = Trip(
            id: id, startDate: visiblePoints[0].timestamp,
            endDate: visiblePoints.last?.timestamp,
            distance: 6_000, maxSpeed: 20, averageSpeed: 10,
            trackPoints: visiblePoints, photos: [],
            title: "legacy response", fuelUsed: 2, elevation: 200,
            region: nil, isPrivate: false, earnedBadgeIds: [])
        local.conflictVersion = 3
        local.lastModifiedAt = start.addingTimeInterval(10_000)
        local.serverCreatedAt = start
        var payload = TripSyncPayload(trip: remoteTrip, entity: local, zone: nil)
        payload.hiddenParts = nil
        payload.hiddenRanges = nil
        let photo = TripPhotoEntity(context: context)
        let photoId = UUID()
        photo.id = photoId
        photo.filename = imageURL.lastPathComponent
        photo.timestamp = start
        photo.capturedAt = localPoints[5].timestamp
        photo.uploadStatus = PhotoUploadStatus.uploaded.rawValue
        photo.trip = local

        repo.applyRemoteTrip(payload)

        let restored = try XCTUnwrap(repo.fetchTripDetail(id: id))
        XCTAssertEqual(restored.trackPoints.map(\.id), localPoints.map(\.id))
        XCTAssertEqual(restored.startDate, start)
        XCTAssertEqual(restored.endDate, localPoints.last?.timestamp)
        XCTAssertEqual(restored.distance, 10_000)
        XCTAssertEqual(restored.maxSpeed, 30)
        XCTAssertEqual(restored.averageSpeed, 12)
        XCTAssertEqual(restored.fuelUsed, 4)
        XCTAssertEqual(restored.elevation, 450)
        XCTAssertEqual(restored.previewPolyline, localPreview)
        XCTAssertEqual((local.photos?.array as? [TripPhotoEntity])?.map(\.id), [photoId])
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
    }
}
