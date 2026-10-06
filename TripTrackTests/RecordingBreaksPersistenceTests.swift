import XCTest
import CoreData
@testable import TripTrack

final class RecordingBreaksPersistenceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testBoundaryIncludesItsTimestampAndSurvivesAccuracyFiltering() {
        let boundary = start.addingTimeInterval(10)
        let points = [
            TrackPoint(latitude: 45, longitude: 39, timestamp: start),
            TrackPoint(latitude: 45, longitude: 40, horizontalAccuracy: 100, timestamp: boundary),
            TrackPoint(latitude: 45, longitude: 40.01, timestamp: boundary.addingTimeInterval(1)),
        ]
        let annotated = RecordingBreaks.annotate(points, breaks: [boundary, boundary])
        XCTAssertEqual(annotated.map(\.recordingSegmentIndex), [0, 1, 1])
        XCTAssertEqual(annotated.filter(\.countsForDistance).map(\.recordingSegmentIndex), [0, 1])
        XCTAssertTrue(RecordingBreaks.crosses(from: start, to: boundary, breaks: [boundary]))
        XCTAssertFalse(RecordingBreaks.crosses(from: boundary, to: boundary.addingTimeInterval(1), breaks: [boundary]))
    }

    func testTripCacheWithoutNewFieldStillDecodesAndDerivedPointIndexIsNotEncoded() throws {
        let point = TrackPoint(latitude: 45, longitude: 39, timestamp: start, recordingSegmentIndex: 7)
        let trip = Trip(trackPoints: [point], recordingBreaks: [start])
        let encoded = try JSONEncoder().encode(trip)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let wirePoint = try XCTUnwrap((json["trackPoints"] as? [[String: Any]])?.first)
        XCTAssertNil(wirePoint["recordingSegmentIndex"])
        json.removeValue(forKey: "recordingBreaks")
        let old = try JSONDecoder().decode(Trip.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.recordingBreaks, [])
        XCTAssertEqual(old.trackPoints.first?.recordingSegmentIndex, 0)
        let restored = try JSONDecoder().decode(Trip.self, from: encoded)
        XCTAssertEqual(restored.recordingBreaks, [start])
        XCTAssertEqual(restored.trackPoints.first?.recordingSegmentIndex, 1)
    }

    func testPersistenceAndSyncPreserveMissingFieldButAllowExplicitClear() throws {
        let pc = PersistenceController(inMemory: true)
        let repo = CoreDataTripRepository(persistenceController: pc)
        let entity = TripEntity(context: pc.container.viewContext)
        let id = UUID()
        entity.id = id
        entity.startDate = start
        entity.endDate = start.addingTimeInterval(100)
        entity.lastModifiedAt = start
        entity.syncStatus = SyncStatus.synced.rawValue
        let boundary = start.addingTimeInterval(10)
        CoreDataTripRepository.setRecordingBreaks([boundary, boundary], on: entity)
        let trip = Trip(id: id, startDate: start, endDate: entity.endDate,
                        trackPoints: [TrackPoint(latitude: 45, longitude: 39, timestamp: start),
                                      TrackPoint(latitude: 45, longitude: 40, timestamp: boundary)],
                        recordingBreaks: [boundary])
        var payload = TripSyncPayload(trip: trip, entity: entity, zone: nil)
        XCTAssertEqual(payload.recordingBreaks, [boundary])
        payload.recordingBreaks = nil
        repo.applyRemoteTrip(payload)
        XCTAssertEqual(CoreDataTripRepository.recordingBreaks(of: entity), [boundary])
        let fetched = try XCTUnwrap(repo.fetchTripDetail(id: id))
        XCTAssertEqual(fetched.recordingBreaks, [boundary])
        XCTAssertEqual(fetched.trackPoints.map(\.recordingSegmentIndex), [0, 1])
        payload.recordingBreaks = []
        repo.applyRemoteTrip(payload)
        XCTAssertEqual(CoreDataTripRepository.recordingBreaks(of: entity), [])
    }

    func testFirstPullRetainsBoundariesDespiteNewEntityDefaultSyncStatus() throws {
        let pc = PersistenceController(inMemory: true)
        let repo = CoreDataTripRepository(persistenceController: pc)
        let metadata = TripEntity(context: pc.container.viewContext)
        metadata.id = UUID()
        metadata.startDate = start
        metadata.lastModifiedAt = start
        let id = UUID()
        let trip = Trip(id: id, startDate: start, endDate: start.addingTimeInterval(30),
                        recordingBreaks: [start.addingTimeInterval(10)])
        let payload = TripSyncPayload(trip: trip, entity: metadata, zone: nil)
        repo.applyRemoteTrip(payload)
        XCTAssertEqual(try XCTUnwrap(repo.fetchTripDetail(id: id)).recordingBreaks, trip.recordingBreaks)
    }

    func testPendingLocalBoundaryIsNotErasedByRemoteMetadata() throws {
        let pc = PersistenceController(inMemory: true)
        let repo = CoreDataTripRepository(persistenceController: pc)
        let entity = TripEntity(context: pc.container.viewContext)
        entity.id = UUID()
        entity.startDate = start
        entity.endDate = start.addingTimeInterval(100)
        entity.lastModifiedAt = start
        entity.syncStatus = SyncStatus.pendingUpload.rawValue
        CoreDataTripRepository.setRecordingBreaks([start.addingTimeInterval(10)], on: entity)
        var payload = TripSyncPayload(trip: Trip(id: entity.id!, startDate: start), entity: entity, zone: nil)
        payload.recordingBreaks = []
        repo.applyRemoteTrip(payload)
        XCTAssertEqual(CoreDataTripRepository.recordingBreaks(of: entity), [start.addingTimeInterval(10)])
    }
}
