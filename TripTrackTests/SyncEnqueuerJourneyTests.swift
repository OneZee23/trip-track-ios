import XCTest
import CoreData
@testable import TripTrack

/// Гейт синка для путешествий (0.6.8). Приватное путешествие — личные данные,
/// как машина: без включённого облака не уезжает никогда. Опубликованное —
/// уезжает, как поездка: `.unpublish` (скрытие) проходит гейт всегда, а
/// `.delete` — только если строка успела доехать до сервера.
///
/// Хранилище ОБЩЕЕ (`PersistenceController.shared`): `SyncEnqueuer`'s приватный
/// `fetchJourneyEntity` читает его напрямую, как `fetchTripEntity`/
/// `fetchPhotoEntity`, — подменить нечем. Строки заводятся руками и руками
/// убираются в `tearDown`, тем же приёмом, что у `VehicleDashboardUnitsWireTests`.
@MainActor
final class SyncEnqueuerJourneyTests: XCTestCase {
    private var insertedIds: [UUID] = []
    private var cloudSyncBefore = false

    override func setUp() {
        super.setUp()
        cloudSyncBefore = SettingsManager.shared.cloudSyncEnabled
        SettingsManager.shared.cloudSyncEnabled = false
        SyncQueue.shared.clearAll()
        // Гейт авторизации — не то, что здесь проверяется (это гейт
        // ПРИВАТНОСТИ); реального входа в юнит-тесте не поставить без живого
        // POST'а, так что он подменяется, как у `SyncQueue.isAuthorizedToSync`.
        SyncEnqueuer.isAuthorizedToEnqueue = { true }
    }

    override func tearDown() {
        let ctx = PersistenceController.shared.container.viewContext
        for id in insertedIds {
            let req: NSFetchRequest<JourneyEntity> = JourneyEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let entity = try? ctx.fetch(req).first { ctx.delete(entity) }
        }
        try? ctx.save()
        insertedIds = []
        SyncQueue.shared.clearAll()
        SettingsManager.shared.cloudSyncEnabled = cloudSyncBefore
        SyncEnqueuer.isAuthorizedToEnqueue = { AuthService.shared.isSignedIn }
        super.tearDown()
    }

    @discardableResult
    private func journey(isPrivate: Bool, serverCreatedAt: Date?) -> UUID {
        let ctx = PersistenceController.shared.container.viewContext
        let e = JourneyEntity(context: ctx)
        let id = UUID()
        e.id = id
        e.createdAt = Date()
        e.startDate = Date()
        e.isPrivate = isPrivate
        e.serverCreatedAt = serverCreatedAt
        e.syncStatus = SyncStatus.pendingUpload.rawValue
        try? ctx.save()
        insertedIds.append(id)
        return id
    }

    private func isQueued(_ id: UUID, _ action: SyncOperation.Action) -> Bool {
        SyncQueue.shared.pending.contains { $0.entityType == .journey && $0.entityId == id && $0.action == action }
    }

    func testPrivateJourneyUploadDeniedWithoutCloud() {
        let id = journey(isPrivate: true, serverCreatedAt: nil)

        SyncEnqueuer.enqueue(SyncOperation(entityType: .journey, entityId: id, action: .upload))

        XCTAssertFalse(isQueued(id, .upload), "личные данные без облака не уезжают")
    }

    func testPublicJourneyUploadPassesWithoutCloud() {
        let id = journey(isPrivate: false, serverCreatedAt: nil)

        SyncEnqueuer.enqueue(SyncOperation(entityType: .journey, entityId: id, action: .upload))

        XCTAssertTrue(isQueued(id, .upload), "опубликованное путешествие уезжает, как поездка")
    }

    func testUnpublishAlwaysPasses() {
        let id = journey(isPrivate: true, serverCreatedAt: Date())

        SyncEnqueuer.enqueue(SyncOperation(entityType: .journey, entityId: id, action: .unpublish))

        XCTAssertTrue(isQueued(id, .unpublish), "скрытие — server-delete половины публикации, обязано дойти")
    }

    func testDeleteGatedByServerCreatedAt() {
        let neverUploaded = journey(isPrivate: true, serverCreatedAt: nil)
        let onServer = journey(isPrivate: true, serverCreatedAt: Date())

        SyncEnqueuer.enqueue(SyncOperation(entityType: .journey, entityId: neverUploaded, action: .delete))
        SyncEnqueuer.enqueue(SyncOperation(entityType: .journey, entityId: onServer, action: .delete))

        XCTAssertFalse(isQueued(neverUploaded, .delete), "нечего удалять на сервере")
        XCTAssertTrue(isQueued(onServer, .delete), "серверная копия существует — удаление уезжает")
    }
}

