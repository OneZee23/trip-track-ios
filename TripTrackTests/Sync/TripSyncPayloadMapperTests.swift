import XCTest
@testable import TripTrack
import CoreData

final class TripSyncPayloadMapperTests: XCTestCase {
    var container: NSPersistentContainer!

    override func setUp() async throws {
        container = NSPersistentContainer(name: "TripTrack")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        let exp = expectation(description: "load")
        container.loadPersistentStores { _, _ in exp.fulfill() }
        await fulfillment(of: [exp], timeout: 5)
    }

    func testBasicTripMapping() throws {
        let ctx = container.viewContext
        let entity = TripEntity(context: ctx)
        let tripId = UUID()
        entity.id = tripId
        entity.startDate = Date(timeIntervalSince1970: 1_700_000_000)
        entity.distance = 1234.5
        entity.conflictVersion = 3
        entity.lastModifiedAt = Date(timeIntervalSince1970: 1_700_001_000)
        entity.badgesJSON = #"["badge1","badge2"]"#
        entity.xpEarned = 150

        let trip = Trip(
            id: tripId,
            startDate: entity.startDate!,
            endDate: nil,
            distance: 1234.5,
            maxSpeed: 20,
            averageSpeed: 10,
            trackPoints: [
                TrackPoint(id: UUID(), latitude: 50.0, longitude: 30.0, altitude: 0,
                           speed: 10, course: 0, horizontalAccuracy: 5,
                           timestamp: Date(), isInterpolated: false)
            ],
            photos: [],
            title: "Morning trip",
            tripDescription: nil,
            fuelUsed: 0.5,
            elevation: 10,
            region: "Berlin",
            isPrivate: false,
            vehicleId: nil,
            fuelCurrency: "€",
            previewPolyline: Data([0xDE, 0xAD, 0xBE, 0xEF]),
            earnedBadgeIds: ["badge1", "badge2"]
        )

        let p = TripSyncPayload(trip: trip, entity: entity)
        XCTAssertEqual(p.id, tripId)
        XCTAssertEqual(p.distance, 1234.5)
        XCTAssertEqual(p.title, "Morning trip")
        XCTAssertEqual(p.region, "Berlin")
        XCTAssertEqual(p.isPrivate, false)
        XCTAssertEqual(p.previewPolyline, "3q2+7w==")
        XCTAssertEqual(p.badgesJson, #"["badge1","badge2"]"#)
        XCTAssertEqual(p.xpEarned, 150)
        XCTAssertEqual(p.conflictVersion, 3)
        XCTAssertEqual(p.trackPoints.count, 1)
        XCTAssertEqual(p.trackPoints.first?.latitude, 50.0)
    }

    func testTripWithNoOptionals() throws {
        let ctx = container.viewContext
        let entity = TripEntity(context: ctx)
        entity.id = UUID()
        entity.startDate = Date()
        entity.conflictVersion = 1
        entity.xpEarned = 0

        let trip = Trip(
            id: entity.id!, startDate: entity.startDate!, endDate: nil,
            distance: 0, maxSpeed: 0, averageSpeed: 0,
            trackPoints: [], photos: [],
            title: nil, tripDescription: nil,
            fuelUsed: 0, elevation: 0, region: nil,
            isPrivate: false, vehicleId: nil, fuelCurrency: nil,
            previewPolyline: nil, earnedBadgeIds: []
        )

        let p = TripSyncPayload(trip: trip, entity: entity)
        XCTAssertNil(p.title)
        XCTAssertNil(p.previewPolyline)
        XCTAssertNil(p.badgesJson)
        XCTAssertEqual(p.trackPoints.count, 0)
    }
}
