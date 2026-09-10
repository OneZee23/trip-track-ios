import XCTest
import CoreData
@testable import TripTrack

/// Путешествие, не уехавшее с первого раза, обязано уехать со второго.
///
/// `SyncQueue` живёт в памяти и умирает вместе с процессом, каскада от
/// `TripEntity` у `JourneyEntity` нет, а `.journey` попадает в очередь ровно
/// из одного места — `JourneyManager`, в момент правки руками. Пока бэкенд не
/// выкачен, каждая такая операция падает в `failedQueue`; без сканирования на
/// старте переотправить её после перезапуска было бы некому, и правка,
/// сделанная в самолёте, осталась бы на телефоне навсегда. Ревью перед
/// сабмитом 0.6.6 нашло ровно это.
final class JourneySyncRecoveryTests: XCTestCase {
    private var pc: PersistenceController!
    private let me = UUID()
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
    }

    @discardableResult
    private func journey(_ status: SyncStatus, userId: UUID? = nil) -> UUID {
        let ctx = pc.container.viewContext
        let e = JourneyEntity(context: ctx)
        let id = UUID()
        e.id = id
        e.startDate = t0
        e.endDate = t0.addingTimeInterval(3 * 86_400)
        e.userId = userId ?? me
        e.syncStatus = status.rawValue
        try? ctx.save()
        return id
    }

    private func recovered() -> [SyncOperation] {
        SyncCoordinator.pendingJourneyOperations(in: pc.container.viewContext, userId: me)
    }

    func testPendingUploadComesBackAsAnUpdate() {
        let id = journey(.pendingUpload)
        let ops = recovered()
        XCTAssertEqual(ops.count, 1)
        XCTAssertEqual(ops.first?.entityType, .journey)
        XCTAssertEqual(ops.first?.entityId, id)
        XCTAssertEqual(ops.first?.action, .update)
    }

    func testPendingDeleteComesBackAsADelete() {
        let id = journey(.pendingDelete)
        let ops = recovered()
        XCTAssertEqual(ops.map(\.entityId), [id])
        XCTAssertEqual(ops.first?.action, .delete)
    }

    /// Синхронизированное путешествие в очереди не нужно: иначе каждый запуск
    /// приложения слал бы на сервер весь список заново.
    func testSyncedJourneyGoesNowhere() {
        journey(.synced)
        XCTAssertTrue(recovered().isEmpty)
    }

    /// Та же защита, что у поездок и машин: свежий вход в другой аккаунт не
    /// тащит в очередь остатки предыдущего.
    func testAnotherAccountsJourneyIsNotPickedUp() {
        journey(.pendingUpload, userId: UUID())
        XCTAssertTrue(recovered().isEmpty)
    }

    /// Оба края разом — и по одной операции на строку, без дублей.
    func testEachPendingRowYieldsExactlyOneOperation() {
        let up = journey(.pendingUpload)
        let gone = journey(.pendingDelete)
        journey(.synced)
        let ops = recovered()
        XCTAssertEqual(Set(ops.map(\.entityId)), [up, gone])
        XCTAssertEqual(ops.filter { $0.action == .update }.map(\.entityId), [up])
        XCTAssertEqual(ops.filter { $0.action == .delete }.map(\.entityId), [gone])
    }
}
