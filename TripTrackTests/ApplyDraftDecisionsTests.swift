import XCTest
import CoreData
@testable import TripTrack

/// `MapViewModel.applyDraftDecisions` — оркестровка «Моя»/«Удалить» (ревью
/// раунда 1: Important 1, Important 2, пункт 5).
///
/// Хранилище ОБЩЕЕ (`PersistenceController.shared`), не изолированное
/// in-memory — вынужденно, как у `JourneyPublishTests`: `MapViewModel` не
/// умеет принять свой репозиторий, а `SyncEnqueuer` читает `.shared`
/// напрямую в своих гейтах. Строки заводятся руками и убираются в `tearDown`.
@MainActor
final class ApplyDraftDecisionsTests: XCTestCase {
    private var vm: MapViewModel!
    private var cloudSyncBefore = false
    private var insertedTripIds: [UUID] = []
    private let t0 = Date(timeIntervalSince1970: 1_765_000_000)

    // «Моя» идёт через полный `processCompletedTrip` — единственную дверь
    // наград, — и пишет опыт в ЖИВУЮ строку настроек `PersistenceController
    // .shared` (ревью раунда 2, пункт 2): без снимка/возврата тест сдвигал
    // бы уровень и стрик человека, который потом откроет тот же симулятор.
    private var savedProfileXP: Int64 = 0
    private var savedProfileLevel: Int32 = 1
    private var savedCurrentStreak: Int32 = 0
    private var savedBestStreak: Int32 = 0
    private var savedLastTripDate: Date?

    // Раунд 1 фикса №1: подменяет `UNUserNotificationCenter.current()` тем же
    // приёмом, что `KeychainHelper.ops` — записью, а не настоящим Центром
    // уведомлений, который в тесте недоступен для проверки.
    private var savedRemoveNotificationIds: (([String]) -> Void)!
    private var removedNotificationIds: [[String]] = []

    override func setUp() {
        super.setUp()
        cloudSyncBefore = SettingsManager.shared.cloudSyncEnabled
        SettingsManager.shared.cloudSyncEnabled = true
        SyncQueue.shared.clearAll()
        // Реального входа в аккаунт в юнит-тесте не поставить — гейт
        // авторизации подменяется, как в `JourneyPublishTests`.
        SyncEnqueuer.isAuthorizedToEnqueue = { true }
        savedRemoveNotificationIds = NotificationManager.shared.removeNotificationIds
        removedNotificationIds = []
        NotificationManager.shared.removeNotificationIds = { [weak self] ids in
            self?.removedNotificationIds.append(ids)
        }
        vm = MapViewModel()
        if let settings = vm.gamificationManager.fetchSettingsEntity() {
            savedProfileXP = settings.profileXP
            savedProfileLevel = settings.profileLevel
            savedCurrentStreak = settings.currentStreak
            savedBestStreak = settings.bestStreak
            savedLastTripDate = settings.lastTripDate
        }
    }

    override func tearDown() {
        let ctx = PersistenceController.shared.container.viewContext
        for id in insertedTripIds {
            let req: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let entity = try? ctx.fetch(req).first { ctx.delete(entity) }
        }
        insertedTripIds = []
        // Возврат — ПОКА `vm` ещё жив: `gamificationManager` его собственный.
        if let settings = vm?.gamificationManager.fetchSettingsEntity() {
            settings.profileXP = savedProfileXP
            settings.profileLevel = savedProfileLevel
            settings.currentStreak = savedCurrentStreak
            settings.bestStreak = savedBestStreak
            settings.lastTripDate = savedLastTripDate
        }
        try? ctx.save()
        _ = DraftDecisionQueue.shared.drain() // не оставить чужому тесту наш мусор
        SyncQueue.shared.clearAll()
        SettingsManager.shared.cloudSyncEnabled = cloudSyncBefore
        SyncEnqueuer.isAuthorizedToEnqueue = { AuthService.shared.isSignedIn }
        NotificationManager.shared.removeNotificationIds = savedRemoveNotificationIds
        removedNotificationIds = []
        vm = nil
        super.tearDown()
    }

    /// Финишированная поездка — строкой напрямую, как у `JourneyPublishTests`:
    /// `TripManager.startTrip`/`stopTrip` тянут геокодер и Live Activity, а
    /// здесь важна только строка в базе с нужным `confirmation`.
    @discardableResult
    private func trip(confirmation: TripConfirmation) -> UUID {
        let ctx = PersistenceController.shared.container.viewContext
        let e = TripEntity(context: ctx)
        let id = UUID()
        e.id = id
        e.startDate = t0
        e.endDate = t0.addingTimeInterval(900)
        e.distance = 5000
        e.maxSpeed = 12
        e.isPrivate = true
        e.confirmation = confirmation.rawValue
        e.userId = SettingsManager.shared.localUserId
        try? ctx.save()
        insertedTripIds.append(id)
        return id
    }

    private func confirmationOf(_ id: UUID) -> String? {
        let req: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? PersistenceController.shared.container.viewContext.fetch(req).first?.confirmation
    }

    private func uploadCount(for id: UUID) -> Int {
        SyncQueue.shared.pending.filter { $0.entityType == .trip && $0.entityId == id && $0.action == .upload }.count
    }

    // MARK: - «Моя»

    func testConfirmFlipsTheRowAndEnqueuesExactlyOneUpload() async {
        let id = trip(confirmation: .draft)
        DraftDecisionQueue.shared.enqueue(id, .confirm)

        await vm.applyDraftDecisions()

        XCTAssertEqual(confirmationOf(id), "confirmed")
        XCTAssertEqual(uploadCount(for: id), 1, "ровно одна .upload — вход в мир не задваивается")
        XCTAssertNil(DraftDecisionQueue.shared.peek(), "решение убрано из очереди")
    }

    /// «Ложь» гварда `setConfirmation` — уже не черновик — не должна тронуть
    /// ничего: ни очередь синка, ни базу.
    func testAlreadyResolvedDecisionIsANoOp() async {
        let id = trip(confirmation: .confirmed)
        DraftDecisionQueue.shared.enqueue(id, .confirm)

        await vm.applyDraftDecisions()

        XCTAssertEqual(uploadCount(for: id), 0, "уже подтверждённая поездка не входит в мир второй раз")
        XCTAssertNil(DraftDecisionQueue.shared.peek(), "запись всё равно убрана — повторять нечего")
    }

    // MARK: - «Удалить»

    /// Important 1, ревью раунда 1: экран итогов и Live Activity не должны
    /// продолжать показывать поездку, которой только что не стало.
    func testDiscardClearsTheOnScreenSummary() async {
        let id = trip(confirmation: .draft)
        vm.lastCompletedTrip = Trip(id: id, confirmation: .draft)
        vm.lastCompletionData = nil

        DraftDecisionQueue.shared.enqueue(id, .discard)
        await vm.applyDraftDecisions()

        XCTAssertNil(vm.lastCompletedTrip, "«Удалить» убирает поездку с экрана итогов")
        XCTAssertNil(vm.lastCompletionData)
        XCTAssertEqual(confirmationOf(id), nil, "строка удалена без следа")
    }

    // MARK: - Пишущаяся поездка

    /// Ревью раунда 1, пункт 5: решение никогда не трогает поездку, которая
    /// ещё пишется — даже если оно как-то оказалось в очереди.
    func testDecisionForTheActiveRecordingTripIsNotApplied() async throws {
        vm.tripManager.startTrip(vehicleId: nil, confirmation: .draft)
        let id = try XCTUnwrap(vm.tripManager.activeTrip?.id)
        insertedTripIds.append(id)
        DraftDecisionQueue.shared.enqueue(id, .confirm)

        await vm.applyDraftDecisions()

        XCTAssertEqual(vm.tripManager.activeTrip?.confirmation, .draft, "решение не тронуло пишущуюся поездку")
        XCTAssertEqual(DraftDecisionQueue.shared.peek()?.0, id, "решение осталось — придёт снова, когда запись кончится")
    }

    // MARK: - Уведомления (раунд 1, фикс №1)

    /// «Удалить» с экрана поездки шёл мимо очереди, звал `tripManager
    /// .deleteTrip` напрямую и не снимал «Твоя?» этой поездки: доставленное
    /// уведомление оставалось с мёртвыми кнопками и тапом в удалённую
    /// поездку. Теперь `deleteTrip` — общая дверь, и её проверяем НАПРЯМУЮ,
    /// в обход очереди — ровно тем путём, которым идёт баннер.
    func testDeleteTripClearsTheDraftPromptId() {
        let id = trip(confirmation: .draft)

        vm.tripManager.deleteTrip(id: id)

        let expected = NotificationManager.draftConfirmId(id)
        XCTAssertTrue(removedNotificationIds.contains { $0.contains(expected) },
                      "прямое удаление черновика обязано снять его «Твоя?»")
        XCTAssertNil(confirmationOf(id), "строка удалена без следа")
    }

    /// Ничего не пишется — общее «Пишу поездку» тоже можно снять: оно не
    /// может относиться ни к какой ЕДУЩЕЙ сейчас записи.
    func testDeleteTripClearsTheStartedNoticeWhenNothingRecords() {
        let id = trip(confirmation: .draft)

        vm.tripManager.deleteTrip(id: id)

        XCTAssertTrue(removedNotificationIds.contains { $0.contains(NotificationManager.draftStartedId) })
    }

    /// Черновик X удалён с экрана, пока поездка Y пишется прямо сейчас:
    /// «Пишу поездку» относится к Y, и удаление X не имеет права его снять.
    func testDeleteTripDoesNotClearTheStartedNoticeWhileAnotherTripRecords() throws {
        vm.tripManager.startTrip(vehicleId: nil, confirmation: .draft)
        let recordingId = try XCTUnwrap(vm.tripManager.activeTrip?.id)
        insertedTripIds.append(recordingId)
        let oldDraft = trip(confirmation: .draft)

        vm.tripManager.deleteTrip(id: oldDraft)

        XCTAssertFalse(removedNotificationIds.contains { $0.contains(NotificationManager.draftStartedId) },
                       "«Пишу поездку» — про поездку Y, старый черновик X его не гасит")
        XCTAssertTrue(removedNotificationIds.contains { $0.contains(NotificationManager.draftConfirmId(oldDraft)) },
                     "«Твоя?» самого X всё равно снимается")
    }

    /// Тот же гейт через очередь: «Удалить» на итогах и «Моя» на итогах/
    /// экране поездки идут через `DraftDecisionQueue`, и результат обязан
    /// совпасть с прямым `deleteTrip` — оба сходятся в одной двери.
    func testDiscardThroughTheQueueDoesNotClearTheStartedNoticeWhileAnotherTripRecords() async throws {
        let oldDraft = trip(confirmation: .draft)
        vm.tripManager.startTrip(vehicleId: nil, confirmation: .draft)
        let recordingId = try XCTUnwrap(vm.tripManager.activeTrip?.id)
        insertedTripIds.append(recordingId)

        DraftDecisionQueue.shared.enqueue(oldDraft, .discard)
        await vm.applyDraftDecisions()

        XCTAssertFalse(removedNotificationIds.contains { $0.contains(NotificationManager.draftStartedId) })
        XCTAssertTrue(removedNotificationIds.contains { $0.contains(NotificationManager.draftConfirmId(oldDraft)) })
    }

    /// «Моя» тоже снимает «Твоя?» этой поездки, и тоже щадит «Пишу поездку»,
    /// пока едет другая запись.
    func testConfirmClearsItsPromptButNotTheStartedNoticeWhileAnotherTripRecords() async throws {
        let oldDraft = trip(confirmation: .draft)
        vm.tripManager.startTrip(vehicleId: nil, confirmation: .draft)
        let recordingId = try XCTUnwrap(vm.tripManager.activeTrip?.id)
        insertedTripIds.append(recordingId)

        DraftDecisionQueue.shared.enqueue(oldDraft, .confirm)
        await vm.applyDraftDecisions()

        XCTAssertTrue(removedNotificationIds.contains { $0.contains(NotificationManager.draftConfirmId(oldDraft)) })
        XCTAssertFalse(removedNotificationIds.contains { $0.contains(NotificationManager.draftStartedId) })
    }
}
