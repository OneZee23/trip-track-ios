import XCTest
import CoreData
@testable import TripTrack

/// APPLE-IOS-X, -V, -W, -B (Sentry, 0.9.0 (88)): главный поток стоит в
/// `TripEntity.trackPointOrder` — внутри сортировки, где у каждой ещё не
/// загруженной точки CoreData идёт в SQLite отдельным запросом. Сортировка
/// теперь идёт по ключам, а незагруженные точки поднимаются одним запросом.
/// Здесь проверено, что порядок от этого не изменился, и сколько он стоит.
@MainActor
final class TrackPointOrderTests: XCTestCase {
    private var pc: PersistenceController!
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("point-order-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        pc = PersistenceController(storeURL: dir.appendingPathComponent("TripTrack.sqlite"))
    }

    override func tearDown() {
        pc = nil
        if let dir { try? FileManager.default.removeItem(at: dir) }
        dir = nil
        super.tearDown()
    }

    /// Прежнее правило словами кода до 0.9.1: время, затем `uuidString`.
    private static func legacyLess(_ a: (Date?, UUID?), _ b: (Date?, UUID?)) -> Bool {
        let ta = a.0 ?? .distantPast, tb = b.0 ?? .distantPast
        if ta != tb { return ta < tb }
        return (a.1?.uuidString ?? "") < (b.1?.uuidString ?? "")
    }

    func testKeyOrderMatchesTheLegacyComparator() {
        var rng = SystemRandomNumberGenerator()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // Много совпадений по времени, пустые время и id — ровно те случаи,
        // где решает второй ключ.
        let items: [(Date?, UUID?)] = (0..<3_000).map { _ in
            let time: Date? = Int.random(in: 0..<20, using: &rng) == 0
                ? nil : base.addingTimeInterval(Double(Int.random(in: 0..<40, using: &rng)))
            let id: UUID? = Int.random(in: 0..<15, using: &rng) == 0 ? nil : UUID()
            return (time, id)
        }
        for _ in 0..<20_000 {
            let a = items.randomElement(using: &rng)!, b = items.randomElement(using: &rng)!
            XCTAssertEqual(
                TrackPointOrderKey(time: a.0, id: a.1) < TrackPointOrderKey(time: b.0, id: b.1),
                Self.legacyLess(a, b))
        }
    }

    func testUUIDBytesOrderLikeTheirString() {
        let low = UUID(uuidString: "0A000000-0000-0000-0000-000000000000")!
        let high = UUID(uuidString: "A0000000-0000-0000-0000-000000000000")!
        let t = Date()
        XCTAssertTrue(TrackPointOrderKey(time: t, id: low) < TrackPointOrderKey(time: t, id: high))
        XCTAssertTrue(TrackPointOrderKey(time: t, id: nil) < TrackPointOrderKey(time: t, id: low))
        XCTAssertFalse(TrackPointOrderKey(time: t, id: low) < TrackPointOrderKey(time: t, id: low))
    }

    /// Точки читаются из НОВОГО контекста, то есть все незагруженные, — тот
    /// путь, на котором приложение и висело. Удалённая в несохранённом
    /// контексте точка остаётся в ответе, как и раньше.
    func testFaultedPointsComeBackInTimeOrder() throws {
        let tripId = try seedTrip(points: 500, shuffled: true)
        let ctx = pc.container.newBackgroundContext()
        try ctx.performAndWait {
            let trip = try XCTUnwrap(fetchTrip(tripId, in: ctx))
            let ordered = trip.orderedTrackPoints
            XCTAssertEqual(ordered.count, 500)
            let keys = ordered.map { ($0.timestamp, $0.id) }
            XCTAssertTrue(zip(keys, keys.dropFirst()).allSatisfy { !Self.legacyLess($1, $0) })

            ctx.delete(ordered[10])
            XCTAssertEqual(trip.orderedTrackPoints.count, 500)
        }
    }

    /// Сколько стоит упорядочить 20 000 незагруженных точек. Прежний путь
    /// меряется рядом и только печатается — для сравнения в журнале прогона.
    func testTwentyThousandFaultedPointsSortWithinBudget() throws {
        let tripId = try seedTrip(points: 20_000, shuffled: false)
        let legacyCtx = pc.container.newBackgroundContext()
        try legacyCtx.performAndWait {
            let trip = try XCTUnwrap(fetchTrip(tripId, in: legacyCtx))
            let start = Date()
            let set = trip.trackPoints as? Set<TrackPointEntity> ?? []
            let sorted = set.sorted { Self.legacyLess(($0.timestamp, $0.id), ($1.timestamp, $1.id)) }
            XCTAssertEqual(sorted.count, 20_000)
            print("[TrackPointOrderTests] legacy: \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        }
        let ctx = pc.container.newBackgroundContext()
        var elapsed: TimeInterval = 0
        try ctx.performAndWait {
            let trip = try XCTUnwrap(fetchTrip(tripId, in: ctx))
            let start = Date()
            XCTAssertEqual(trip.orderedTrackPoints.count, 20_000)
            elapsed = Date().timeIntervalSince(start)
        }
        print("[TrackPointOrderTests] keys: 20k faulted points ordered in \(Int(elapsed * 1000)) ms")
        XCTAssertLessThan(elapsed, 0.5)
    }

    private func seedTrip(points: Int, shuffled: Bool) throws -> UUID {
        let ctx = pc.container.viewContext
        let trip = TripEntity(context: ctx)
        let tripId = UUID()
        trip.id = tripId
        trip.startDate = Date(timeIntervalSince1970: 1_700_000_000)
        var offsets = Array(0..<points)
        if shuffled { offsets.shuffle() }
        for i in offsets {
            let p = TrackPointEntity(context: ctx)
            p.id = UUID()
            p.latitude = 52 + Double(i) * 1e-5
            p.longitude = 76
            // Каждые десять точек делят секунду — второй ключ работает.
            p.timestamp = trip.startDate!.addingTimeInterval(Double(i / 10))
            p.trip = trip
        }
        try ctx.save()
        ctx.reset()
        return tripId
    }

    private func fetchTrip(_ id: UUID, in ctx: NSManagedObjectContext) throws -> TripEntity? {
        let request = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try ctx.fetch(request).first
    }
}
