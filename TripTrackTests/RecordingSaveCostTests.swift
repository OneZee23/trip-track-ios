import XCTest
import CoreData
@testable import TripTrack

/// APPLE-IOS-P (Sentry, 9 окт 2026): 22 зависания ≥ 2 с за одну поездку на
/// iPhone 15 Pro Max / iOS 17.6.1, главный поток стоит в `save` →
/// `_NSFaultingMutableOrderedSet _orderKeyForObject:` →
/// `indexOfObjectIdenticalTo`. Связь `trackPoints` упорядоченная, и каждая
/// новая точка ищется линейно среди уже записанных. Здесь — та же запись,
/// что делает `TripManager` (точка привязывается `point.trip = entity`, пачка
/// сохраняется), на настоящем SQLite: сколько стоит ОДНО сохранение пачки,
/// когда в поездке уже N точек.
@MainActor
final class RecordingSaveCostTests: XCTestCase {
    private var pc: PersistenceController!
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-save-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        pc = PersistenceController(storeURL: dir.appendingPathComponent("TripTrack.sqlite"))
    }

    override func tearDown() {
        pc = nil
        if let dir { try? FileManager.default.removeItem(at: dir) }
        dir = nil
        super.tearDown()
    }

    /// Проверено и НЕ помогает (10 окт 2026): дописывать в конец через
    /// `mutableOrderedSetValue` и сбрасывать поездку после сохранения — цена
    /// та же, CoreData пересчитывает ключи порядка всей связи на каждом save.
    enum Attach { case inverse, appendOrdered, inverseRefreshed }
    private var attach: Attach = .inverse

    private func addPoints(_ n: Int, to trip: TripEntity, from start: Int, in ctx: NSManagedObjectContext) {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        for i in start..<(start + n) {
            let p = TrackPointEntity(context: ctx)
            p.id = UUID()
            p.latitude = 52 + Double(i) * 1e-5
            p.longitude = 76
            p.speed = 20
            p.horizontalAccuracy = 5
            p.timestamp = t0.addingTimeInterval(Double(i))
            switch attach {
            case .inverse: p.trip = trip
            case .appendOrdered: trip.mutableOrderedSetValue(forKey: "trackPoints").add(p)
            case .inverseRefreshed: p.trip = trip
            }
        }
    }

    /// Возвращает время сохранения пачки из `batch` точек при `existing` уже
    /// записанных, в миллисекундах.
    private func batchSaveMs(existing: Int, batch: Int = 10) throws -> Double {
        let ctx = pc.container.viewContext
        let trip = TripEntity(context: ctx)
        trip.id = UUID()
        trip.startDate = Date()
        // Прогоняем трек до `existing` пачками, как запись, чтобы связь была
        // в том же состоянии, что у живой поездки.
        var added = 0
        while added < existing {
            let n = min(2_000, existing - added)
            addPoints(n, to: trip, from: added, in: ctx)
            try ctx.save()
            if attach == .inverseRefreshed { ctx.refresh(trip, mergeChanges: false) }
            added += n
        }
        addPoints(batch, to: trip, from: added, in: ctx)
        let t = Date()
        try ctx.save()
        return Date().timeIntervalSince(t) * 1000
    }

    func testBatchSaveCostGrowsWithTrackLength() throws {
        for mode in [Attach.inverse, .inverseRefreshed] {
            attach = mode
            var rows: [String] = []
            for n in [1_000, 10_000, 30_000, 60_000] {
                let ms = try batchSaveMs(existing: n)
                rows.append("\(n): \(String(format: "%.1f", ms)) ms")
            }
            print("RecordingSaveCost \(mode): " + rows.joined(separator: ", "))
        }
    }

    /// Сторож: пока цена растёт квадратично, длинная запись подвешивает
    /// главный поток. Порог — 60 000 точек (~17 ч записи раз в секунду) за
    /// 2 с на Mac; сегодня ~570 мс, на телефоне в 3–5 раз дольше. Тест не
    /// чинит, а не даёт сделать хуже незаметно.
    func testLongTrackBatchSaveStaysUnderTwoSecondsOnMac() throws {
        attach = .inverse
        XCTAssertLessThan(try batchSaveMs(existing: 60_000), 2_000)
    }
}
