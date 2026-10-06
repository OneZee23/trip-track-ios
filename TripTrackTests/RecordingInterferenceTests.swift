import CoreData
import CoreLocation
import Combine
import XCTest
@testable import TripTrack

@MainActor
final class RecordingInterferenceTests: XCTestCase {
    private func fix(_ north: Double, at seconds: Double, speed: Double = 15,
                     accuracy: Double = 8, course: Double = 0) -> CLLocation {
        TrackTestKit.fix(east: 0, north: north, speed: speed, course: course,
                         after: seconds, accuracy: accuracy)
    }

    private func makeRecording(now: @escaping () -> Date = Date.init) -> (TripManager, PersistenceController) {
        let pc = PersistenceController(inMemory: true)
        let manager = TripManager(locationManager: LocationManager(), persistenceController: pc,
                                  recordingNow: now)
        manager.startTrip(vehicleId: nil)
        return (manager, pc)
    }

    private func points(_ pc: PersistenceController) throws -> [TrackPointEntity] {
        let request: NSFetchRequest<TrackPointEntity> = TrackPointEntity.fetchRequest()
        return try pc.container.viewContext.fetch(request).sorted {
            ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast)
        }
    }

    func testTeleportNeverReachesShapeAndNextGoodFixRecovers() throws {
        let (manager, pc) = makeRecording()
        var drawn: [CLLocation] = []
        let subscription = manager.recordedLocationPublisher.sink { drawn.append($0) }
        defer { subscription.cancel() }
        (0...30).forEach { manager.handleNewLocation(fix(Double($0) * 15, at: Double($0))) }
        manager.handleNewLocation(fix(1_050, at: 31, speed: 0, accuracy: 42))
        manager.handleNewLocation(fix(480, at: 32))

        let saved = try points(pc)
        XCTAssertFalse(saved.contains { $0.timestamp == TrackTestKit.epoch.addingTimeInterval(31) })
        let last = try XCTUnwrap(saved.last)
        XCTAssertEqual(last.timestamp, TrackTestKit.epoch.addingTimeInterval(32))
        XCTAssertLessThan(CLLocation(latitude: last.latitude, longitude: last.longitude)
            .distance(from: fix(480, at: 32)), 15)
        XCTAssertLessThanOrEqual(manager.activeTrip?.maxSpeed ?? .infinity, 20)
        XCTAssertEqual(drawn.count, saved.count)
        XCTAssertFalse(drawn.contains { $0.timestamp == TrackTestKit.epoch.addingTimeInterval(31) })
    }

    func testCoarseTeleportCannotPoisonTheFollowingGoodMeasurement() {
        var gate = RecordingFixContinuity()
        XCTAssertNil(gate.rejection(for: fix(0, at: 0, accuracy: 120)))
        XCTAssertEqual(gate.rejection(for: fix(240, at: 1, speed: 0, accuracy: 120)), .displacement)
        XCTAssertNil(gate.rejection(for: fix(30, at: 2)))
    }

    func testDuplicateAndReorderedTimestampsDoNotMoveTheRawAnchor() {
        var gate = RecordingFixContinuity()
        XCTAssertNil(gate.rejection(for: fix(0, at: 10)))
        XCTAssertEqual(gate.rejection(for: fix(1_000, at: 10)), .timestamp)
        XCTAssertEqual(gate.rejection(for: fix(1_000, at: 9)), .timestamp)
        XCTAssertNil(gate.rejection(for: fix(15, at: 11)))
    }

    func testSparseRealDriveStillCountsAcrossTwoMinuteSignalGap() throws {
        let (manager, pc) = makeRecording()
        manager.handleNewLocation(fix(0, at: 0, speed: 42))
        manager.handleNewLocation(fix(5_000, at: 120, speed: 42, course: -1))
        let saved = try points(pc)
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(manager.activeTrip?.distance ?? 0, 5_000, accuracy: 30)
        XCTAssertEqual(manager.activeTrip?.maxSpeed ?? 0, 42, accuracy: 0.01)
    }

    func testDenseGenuineHighwayMeasurementsAreNotThrottled() {
        var gate = RecordingFixContinuity()
        for index in 0...100 {
            XCTAssertNil(gate.rejection(for: fix(Double(index) * 4, at: Double(index) / 10, speed: 40)))
        }
    }

    func testSparseUnknownSpeedDoesNotBecomeAStationaryFix() throws {
        let (manager, pc) = makeRecording()
        manager.backdateTrip(to: TrackTestKit.epoch)
        for index in 0...2 {
            let raw = fix(Double(index) * 5_000, at: Double(index) * 120,
                          speed: -1, course: -1)
            manager.handleNewLocation(LocationUpdate.from(raw).toCLLocation())
        }
        XCTAssertEqual(try points(pc).count, 3)
        XCTAssertEqual(manager.activeTrip?.distance ?? 0, 10_000, accuracy: 60)
        let preview = try XCTUnwrap(manager.recordingFinishPreview(now: TrackTestKit.epoch.addingTimeInterval(240)))
        XCTAssertGreaterThan(preview.maxSpeed, 40)
        XCTAssertNil(preview.discardReason)
    }

    func testLongGapEndingStoppedKeepsDistanceAndDoesNotDiscardTheDrive() throws {
        let (manager, pc) = makeRecording()
        manager.backdateTrip(to: TrackTestKit.epoch)
        manager.handleNewLocation(fix(0, at: 0, speed: 0))
        manager.handleNewLocation(fix(5_000, at: 240, speed: 0, course: -1))
        let saved = try points(pc)
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved.last?.speed, 0, "Arrival is stopped; the gap average is not an instantaneous speed")
        let preview = try XCTUnwrap(manager.recordingFinishPreview(now: TrackTestKit.epoch.addingTimeInterval(240)))
        XCTAssertEqual(preview.distance, 5_000, accuracy: 30)
        XCTAssertGreaterThan(preview.maxSpeed, 20, "The trusted displacement gives a lower bound on the trip maximum")
        XCTAssertNil(preview.discardReason)
    }

    func testInterruptedSparseDriveEndingStoppedSurvivesOrphanRecovery() throws {
        let pause = Date().addingTimeInterval(-5)
        let (manager, pc) = makeRecording(now: { pause })
        let start = pause.addingTimeInterval(-241)
        manager.backdateTrip(to: start)
        func timed(_ north: Double, at timestamp: Date) -> CLLocation {
            CLLocation(coordinate: TrackTestKit.coordinate(east: 0, north: north),
                       altitude: 30, horizontalAccuracy: 8, verticalAccuracy: 3,
                       course: -1, speed: 0, timestamp: timestamp)
        }
        manager.handleNewLocation(timed(0, at: start))
        manager.handleNewLocation(timed(5_000, at: start.addingTimeInterval(240)))
        manager.isPaused = true // Boundary and last point become durable.
        let id = try XCTUnwrap(manager.activeTrip?.id)
        let restored = TripManager(locationManager: LocationManager(), persistenceController: pc)
        XCTAssertEqual(restored.recoverableOrphan?.id, id)
        XCTAssertEqual(restored.recoverableOrphan?.recordingBreaks, [pause])
        XCTAssertGreaterThan(restored.recoverableOrphan?.maxSpeed ?? 0, 20)
        XCTAssertNotNil(restored.repository.fetchTripDetail(id: id))
    }

    func testCorrelatedFalseFixBurstDoesNotDrawASpiral() throws {
        let (manager, pc) = makeRecording()
        (0...30).forEach { manager.handleNewLocation(fix(Double($0) * 10, at: Double($0), speed: 10)) }
        for index in 0..<53 {
            manager.handleNewLocation(fix(530, at: 31 + Double(index) * 0.004,
                                          speed: -1, accuracy: 32, course: -1))
        }
        manager.handleNewLocation(fix(320, at: 32, speed: 10))
        let saved = try points(pc)
        XCTAssertEqual(saved.count, 32)
        XCTAssertLessThan(manager.activeTrip?.distance ?? .infinity, 340)
        XCTAssertLessThan(manager.activeTrip?.maxSpeed ?? .infinity, 15)
    }

    func testResumeDoesNotInheritPrePauseVelocity() throws {
        let (manager, pc) = makeRecording()
        (0...30).forEach { manager.handleNewLocation(fix(Double($0) * 30, at: Double($0), speed: 30)) }
        manager.isPaused = true
        manager.handleNewLocation(fix(10_000, at: 300))
        manager.isPaused = false
        manager.handleNewLocation(fix(910, at: 600, speed: 0, course: -1))
        let last = try XCTUnwrap(points(pc).last)
        XCTAssertEqual(last.speed, 0)
        XCTAssertLessThan(CLLocation(latitude: last.latitude, longitude: last.longitude)
            .distance(from: fix(910, at: 600)), 0.1)
    }

    func testPausedMovementStaysExcludedAfterFinalRecalculationAndReload() throws {
        let boundary = TrackTestKit.epoch.addingTimeInterval(40)
        let (manager, pc) = makeRecording(now: { boundary })
        (0...30).forEach { manager.handleNewLocation(fix(Double($0) * 15, at: Double($0))) }
        manager.isPaused = true
        manager.isPaused = true // Repeated state assignment is not another pause.
        manager.handleNewLocation(fix(5_000, at: 300))
        manager.isPaused = false
        manager.handleNewLocation(fix(10_000, at: 600))
        manager.handleNewLocation(fix(10_015, at: 601))
        manager.handleNewLocation(fix(10_030, at: 602))

        let preview = try XCTUnwrap(manager.recordingFinishPreview())
        XCTAssertEqual(preview.distance, 480, accuracy: 10)
        XCTAssertEqual(manager.activeTrip?.recordingBreaks, [boundary])
        pc.save()
        let restored = try XCTUnwrap(manager.repository.fetchTripDetail(id: preview.tripID))
        XCTAssertEqual(restored.recordingBreaks, [boundary])
        XCTAssertEqual(Set(restored.measuredPoints.map(\.recordingSegmentIndex)), [0, 1])
    }

    func testStopPreviewDiscardsImpossibleRecordInsteadOfClampingIt() throws {
        let (manager, pc) = makeRecording()
        (0...3).forEach { manager.handleNewLocation(fix(Double($0) * 15, at: Double($0))) }
        let saved = try points(pc)
        try XCTUnwrap(saved.last).speed = 1_000
        XCTAssertEqual(try XCTUnwrap(manager.recordingFinishPreview()).maxSpeed, 15, accuracy: 0.5)
    }

    func testPostProcessingCannotRestoreImpossibleSpeedRecord() async throws {
        let pc = PersistenceController(inMemory: true)
        let trip = TrackTestKit.insertTrip(into: pc, points: [
            .init(east: 0, north: 0, seconds: 0, speed: 15),
            .init(east: 0, north: 150, seconds: 10, speed: 1_000),
            .init(east: 0, north: 300, seconds: 20, speed: 20)
        ])
        await PostTripTrackProcessor(persistenceController: pc).processTrip(try XCTUnwrap(trip.id))
        XCTAssertEqual(trip.maxSpeed, 20)
        XCTAssertEqual(trip.distance, 300, accuracy: 3)
    }

    func testSpeedRecordRejectsNonFiniteAndUnknownValues() {
        for speed in [Double.nan, .infinity, -.infinity, -1, 1_000] {
            XCTAssertFalse(TripDistanceGate.isPlausibleSpeed(speed))
        }
        XCTAssertTrue(TripDistanceGate.isPlausibleSpeed(0))
        XCTAssertTrue(TripDistanceGate.isPlausibleSpeed(80))
    }
}
