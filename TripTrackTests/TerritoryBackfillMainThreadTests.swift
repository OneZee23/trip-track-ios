import XCTest
import CoreData
@testable import TripTrack

/// Sentry AppHang ≥ 2000 мс, 0.6.8/0.7.0, первый запуск после обновления
/// магазина: `TerritoryManager.backfillIfNeeded()` поднимало ВСЮ библиотеку
/// трек-точек на `viewContext` одним синхронным циклом без единой точки
/// уступки, и на зрелой библиотеке (сотни тысяч точек) это держало главный
/// поток секундами. Фикс переносит фетч, геохэш и запись на фоновый
/// контекст — главный актёр получает только готовый список хэшей одним
/// прыжком (см. `TerritoryManager.backfillIfNeeded`).
///
/// `@MainActor`: тест `async` и трогает `viewContext` — см. CLAUDE.md
/// «async-тест, читающий viewContext, обязан быть @MainActor».
@MainActor
final class TerritoryBackfillMainThreadTests: XCTestCase {
    private var pc: PersistenceController!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        suiteName = "territory-hang-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        pc = nil
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// Библиотека «стресс», близкая по масштабу к брифу H (400×2000): здесь
    /// уже 200×1500 = 300 000 точек — этого достаточно, чтобы синхронный
    /// цикл по всем точкам на главном потоке было видно за секунды, а
    /// полный прогон тестов не растягивать до предела CI. `-seed-hang-stress`
    /// (`DebugMapSeed`) даёт полный масштаб брифа для ручной проверки на
    /// устройстве/симуляторе.
    private func seedStressLibrary(trips: Int = 200, pointsPerTrip: Int = 1500) {
        let ctx = pc.container.viewContext
        let base = Date(timeIntervalSince1970: 1_760_000_000)
        for t in 0..<trips {
            autoreleasepool {
                let trip = TripEntity(context: ctx)
                trip.id = UUID()
                let start = base.addingTimeInterval(-Double(t) * 3600)
                trip.startDate = start
                trip.endDate = start.addingTimeInterval(Double(pointsPerTrip) * 5)
                trip.isPrivate = true
                let latBase = 45.0 + Double(t) * 0.01
                let lonBase = 38.9 + Double(t) * 0.01
                for p in 0..<pointsPerTrip {
                    let point = TrackPointEntity(context: ctx)
                    point.id = UUID()
                    point.latitude = latBase + Double(p) * 0.00003
                    point.longitude = lonBase + Double(p) * 0.00002
                    point.timestamp = start.addingTimeInterval(Double(p) * 5)
                    point.trip = trip
                }
            }
            if t % 40 == 0 { try? ctx.save() }
        }
        try? ctx.save()
    }

    /// До фикса: тот же алгоритм, что раньше жил в `TerritoryManager
    /// .backfillIfNeeded()`, инлайнен здесь ТОЛЬКО ради замера «было» — сам
    /// продакшен-код больше так не делает (см. фикс), а исходную версию
    /// держит `git log` на `fix/hang`, а не рабочее дерево. Возвращает
    /// Возвращает elapsed-время алгоритма в мс. Сторож здесь не нужен: у
    /// старого алгоритма нет НИ ОДНОЙ точки уступки (`await`/`Task.yield`)
    /// между первой строкой и последним `save()` — значит чем бы он ни
    /// выполнялся, элапсед этой функции И ЕСТЬ время, на которое звонящий
    /// поток не мог сделать ничего другого. `DispatchQueue.main.sync`
    /// дополнительно проецирует это на главную очередь без риска
    /// взаимной блокировки (не звонит `sync` с той же очереди).
    private func measureOldSynchronousAlgorithmElapsedMs() -> Double {
        let context = pc.container.viewContext
        let runOnMain: (() -> Void) -> Void = Thread.isMainThread
            ? { body in body() }
            : { body in DispatchQueue.main.sync(execute: body) }

        let started = Date()
        runOnMain {
            let request: NSFetchRequest<TrackPointEntity> = TrackPointEntity.fetchRequest()
            request.fetchBatchSize = 500
            request.propertiesToFetch = ["latitude", "longitude", "timestamp"]
            guard let points = try? context.fetch(request) else { return }

            var visited = Set<String>()
            var newHashes: [(String, Date)] = []
            for point in points {
                let hash6 = GeohashEncoder.encode(latitude: point.latitude, longitude: point.longitude, precision: 6)
                if !visited.contains(hash6) {
                    visited.insert(hash6)
                    newHashes.append((hash6, point.timestamp ?? Date()))
                }
            }
            let batchSize = 500
            for i in stride(from: 0, to: newHashes.count, by: batchSize) {
                let batch = newHashes[i..<min(i + batchSize, newHashes.count)]
                for (hash, date) in batch {
                    let entity = VisitedGeohashEntity(context: context)
                    entity.hash6 = hash
                    entity.firstVisited = date
                    entity.lastVisited = date
                    entity.visitCount = 1
                }
                try? context.save()
            }
        }
        return Date().timeIntervalSince(started) * 1000
    }

    /// «Было»: печатается всегда — фиксирует масштаб проблемы, не проверка.
    /// Не гейт CI (без `XCTAssert` на потолок) — это ИМЕННО повторение
    /// старого поведения, у него нет бюджета, который он обязан пройти.
    func testOldSynchronousAlgorithmBlockedMainForStressLibrary() {
        seedStressLibrary()
        let elapsedMs = measureOldSynchronousAlgorithmElapsedMs()
        print(String(format: "[territory backfill] БЫЛО: главный поток стоял %.0f мс без единой уступки", elapsedMs))
        XCTAssertGreaterThan(elapsedMs, 500,
            "синтетика должна была хоть раз держать главный поток дольше полсекунды — иначе стресс-сид слишком мал, чтобы что-то доказывать")
    }

    /// «Стало»: продакшен-фикс, тот же стресс. Бюджет 200 мс — по образцу
    /// `DiscoveryProcessorTests`/`MapRenderCostTests`: печатается всегда,
    /// падает, если главный поток снова встанет в очередь фонового счёта.
    func testBackfillIfNeededKeepsMainResponsiveUnderStress() async {
        seedStressLibrary()
        let tm = TerritoryManager(persistenceController: pc, defaults: defaults)

        let watchdog = MainThreadWatchdog()
        watchdog.start()
        let started = Date()
        await tm.backfillIfNeeded()
        let elapsed = Date().timeIntervalSince(started)
        Thread.sleep(forTimeInterval: 0.05)
        watchdog.stop()

        print(String(format: "[territory backfill] СТАЛО: главный поток стоял максимум %.0f мс, весь проход %.0f мс",
                     watchdog.maxGapMs, elapsed * 1000))
        XCTAssertTrue(defaults.bool(forKey: TerritoryManager.backfillKey))
        XCTAssertLessThan(watchdog.maxGapMs, 200,
            "backfillIfNeeded держал главный поток дольше 200 мс на стрессовой библиотеке — фон снова просочился на main")
    }
}
