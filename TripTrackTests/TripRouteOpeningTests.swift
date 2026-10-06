import XCTest
import CoreLocation
@testable import TripTrack

@MainActor
final class TripRouteOpeningTests: XCTestCase {
    private func points(_ count: Int) -> [TrackPoint] {
        (0..<count).map { i in
            TrackPoint(latitude: 45 + Double(i) * 0.00001,
                       longitude: 39 + sin(Double(i) / 50) * 0.01,
                       speed: Double(i), timestamp: TrackTestKit.epoch.addingTimeInterval(Double(i)))
        }
    }

    func testLongReplayPreservesEndpointsOrderAndAlignedReadings() async throws {
        let source = points(3_000)
        let replay = try await TripReplayInput.prepare(points: source)
        XCTAssertLessThanOrEqual(replay.coords.count, 300)
        XCTAssertGreaterThan(replay.coords.count, 2)
        XCTAssertEqual(replay.speeds.first, 0)
        XCTAssertEqual(replay.speeds.last, 2_999)
        XCTAssertEqual(replay.speeds, replay.speeds.sorted())
        XCTAssertEqual(replay.timestamps.count, replay.coords.count)
        for i in replay.coords.indices {
            let original = source[Int(replay.speeds[i])]
            XCTAssertEqual(replay.coords[i].latitude, original.latitude)
            XCTAssertEqual(replay.coords[i].longitude, original.longitude)
            XCTAssertEqual(replay.timestamps[i], original.timestamp)
        }
    }

    func testShortRouteKeepsEveryPointAndPreviewHasNoInventedReplayTimes() {
        let source = points(25)
        let replay = TripReplayInput(points: source)
        XCTAssertEqual(replay.speeds, source.map(\.speed))
        XCTAssertEqual(replay.timestamps, source.map(\.timestamp))
        let preview = TripReplayInput(coords: points(1_000).map(\.coordinate), speeds: [], timestamps: [])
        XCTAssertFalse(preview.coords.isEmpty)
        XCTAssertTrue(preview.speeds.isEmpty)
        XCTAssertTrue(preview.timestamps.isEmpty)
    }

    func testCancelledPreparationCannotPublishAReplay() async {
        let task = Task {
            try Task.checkCancellation()
            return try await TripReplayInput.prepare(points: self.points(3_000))
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled screen must not publish replay data")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testBackgroundDetailKeepsSavedTrackAndSeesDeletion() async throws {
        let pc = PersistenceController(inMemory: true)
        let repo = CoreDataTripRepository(persistenceController: pc)
        var specs: [TrackTestKit.PointSpec] = []
        for i in 0..<1_000 {
            let east = Double(i) * 5.0
            let north = Double(i % 20)
            let speed = Double(i % 30)
            specs.append(TrackTestKit.PointSpec(east: east, north: north,
                                                seconds: Double(i), speed: speed))
        }
        let entity = TrackTestKit.insertTrip(into: pc, points: specs)
        let id = try XCTUnwrap(entity.id)
        let expected = try XCTUnwrap(repo.fetchTripDetail(id: id))
        let loaded = await repo.fetchTripDetailAsync(id: id)
        let actual = try XCTUnwrap(loaded)
        XCTAssertEqual(actual.id, expected.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(actual.trackPoints), try encoder.encode(expected.trackPoints))
        XCTAssertEqual(actual.photos, expected.photos)
        XCTAssertEqual(actual.checkpoints, expected.checkpoints)
        pc.container.viewContext.delete(entity)
        try pc.container.viewContext.save()
        let deleted = await repo.fetchTripDetailAsync(id: id)
        XCTAssertNil(deleted)
    }
}
