import XCTest
@testable import TripTrack

/// Трек поездки с сайта — до `ManualTripTrackLoader.maximumPoints` точек —
/// пишется в CoreData ВНЕ главного актёра (`applyMissingManualTrackAsync`).
/// На главном вставка и сохранение десяти тысяч строк стоили ~260 мс
/// (симулятор, SQLite) — заметная заминка при открытии экрана.
///
/// Меряется ПРЯМО: время синхронных участков загрузчика на главном актёре.
/// `MainThreadWatchdog` здесь слеп — его пробы стоят в `DispatchQueue.main`,
/// а тест держит главный актёр своей задачей, и XCTest не выполняет очередь,
/// пока она не уступит (замер показывал 0 мс при 260 мс работы на главном).
@MainActor
final class ManualTripHydrationBudgetTests: XCTestCase {
    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!
    private var dir: URL!

    /// Настоящий SQLite во временном файле, а не стор в памяти: в памяти
    /// сохранение десяти тысяч строк почти бесплатно, и замер ничего не
    /// говорил бы о телефоне, который пишет на диск.
    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hydration-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        pc = PersistenceController(storeURL: dir.appendingPathComponent("TripTrack.sqlite"))
        repo = CoreDataTripRepository(persistenceController: pc)
    }

    override func tearDown() {
        repo = nil
        pc = nil
        if let dir { try? FileManager.default.removeItem(at: dir) }
        dir = nil
        super.tearDown()
    }

    func testMaximumWebRouteHydratesWithinTheMainThreadBudget() async throws {
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let n = ManualTripTrackLoader.maximumPoints
        let points = (0..<n).map { i in
            TrackPointPayload(id: UUID(), latitude: 45 + Double(i) * 1e-5, longitude: 39,
                              altitude: 0, speed: 10, course: 0, horizontalAccuracy: -1,
                              timestamp: start.addingTimeInterval(Double(i)), isInterpolated: false)
        }
        let summary = TripSyncPayload(
            id: id, title: "Web trip", description: nil,
            startDate: start, endDate: start.addingTimeInterval(Double(n)),
            distance: 100_000, maxSpeed: 10, averageSpeed: 10,
            fuelUsed: 0, elevation: 0, maxAltitude: nil, drivingTime: n,
            stoppedTime: 0, region: nil, isPrivate: true, vehicleId: nil,
            fuelCurrency: nil, previewPolyline: nil, badgesJson: "[]", xpEarned: 0,
            conflictVersion: 1, lastModifiedAt: start.addingTimeInterval(Double(n) + 60),
            serverCreatedAt: start.addingTimeInterval(Double(n) + 60), trackPoints: nil,
            photos: nil, source: .manual, energyMode: nil)
        repo.applyRemoteTrip(summary)
        repo.flushPendingApplies()
        let full = TripSyncPayload(
            id: id, title: summary.title, description: nil,
            startDate: summary.startDate, endDate: summary.endDate,
            distance: summary.distance, maxSpeed: 10, averageSpeed: 10,
            fuelUsed: 0, elevation: 0, maxAltitude: nil, drivingTime: summary.drivingTime,
            stoppedTime: 0, region: nil, isPrivate: true, vehicleId: nil,
            fuelCurrency: nil, previewPolyline: nil, badgesJson: "[]", xpEarned: 0,
            conflictVersion: 1, lastModifiedAt: summary.lastModifiedAt,
            serverCreatedAt: summary.serverCreatedAt, trackPoints: points,
            photos: nil, source: .manual, energyMode: nil)
        let owner = UUID()
        let loader = ManualTripTrackLoader(repository: repo, accountId: { owner },
                                           cloudSyncEnabled: { true },
                                           fetch: { _ in full }, afterLoad: { _ in })

        // Главный актёр занят, пока НЕ спит: стоящая рядом задача на главном
        // актёре считает, сколько раз ей удалось выполниться. Каждые 10 мс
        // свободного главного — тик; 260 мс блокировки дали бы дыру без тиков.
        let ticker = Task { @MainActor () -> Double in
            var last = Date(), worst = 0.0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
                let now = Date()
                worst = max(worst, now.timeIntervalSince(last) * 1000)
                last = now
            }
            return worst
        }
        let clock = Date()
        let trip = await loader.loadIfNeeded(id: id)
        let totalMs = Date().timeIntervalSince(clock) * 1000
        ticker.cancel()
        let worstGapMs = await ticker.value

        XCTAssertEqual(trip?.trackPoints.count, n)
        print("ManualTripHydrationBudget: \(n) points, total \(Int(totalMs)) ms, worst main-actor gap \(Int(worstGapMs)) ms")
        XCTAssertLessThan(worstGapMs, 100, "hydration held the main actor for \(Int(worstGapMs)) ms")
    }

    /// Контроль измерителя: заведомая блокировка главного актёра на 300 мс
    /// обязана дать дыру в тиках не меньше 250 мс. Без этого «мало» выше могло
    /// бы значить «измеритель слеп», а не «главный свободен».
    func testTickerSeesAKnownMainActorStall() async {
        let ticker = Task { @MainActor () -> Double in
            var last = Date(), worst = 0.0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
                let now = Date()
                worst = max(worst, now.timeIntervalSince(last) * 1000)
                last = now
            }
            return worst
        }
        try? await Task.sleep(for: .milliseconds(50))
        let until = Date().addingTimeInterval(0.3)
        while Date() < until {}
        try? await Task.sleep(for: .milliseconds(50))
        ticker.cancel()
        let gap = await ticker.value
        print("ManualTripHydrationBudget control: known 300 ms stall measured as \(Int(gap)) ms")
        XCTAssertGreaterThan(gap, 250)
    }
}
