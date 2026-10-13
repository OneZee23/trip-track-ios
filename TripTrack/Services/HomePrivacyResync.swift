import Combine
import CoreData
import Foundation
import os

/// Переотправка уже опубликованных поездок после смены приватной зоны (0.8.2).
///
/// Решение владельца 27 сентября: включение зоны (и передвинутый дом, и
/// сменённый радиус при включённой зоне) ПЕРЕОТПРАВЛЯЕТ все уже
/// опубликованные поездки обрезанными. Иначе обещание приватности ложное —
/// тумблер стоит, а вчерашний трек от подъезда уже лежит в чужой ленте, и сам
/// он оттуда не уйдёт никогда.
///
/// Сервер при этом не трогается вовсе: обрезка живёт в сборке
/// `TripSyncPayload`, а здесь только «сходи и отправь заново». Отсюда и форма —
/// не свой транспорт, а обычная очередь синка: та уже умеет дедупликацию,
/// повторы, порядок и чанк по БАЙТАМ (`SyncChunkBudget`), и второй дороги на
/// сервер заводить нельзя.
///
/// Подписка, а не прямой вызов из листа настройки: лист ничего не знает про
/// очередь синка, а переотправка — про лист. Форма скопирована у
/// `RevealedLayerSync` (дверь пула в открытый мир), включая инжекцию
/// `NotificationCenter` ради тестов.
@MainActor
final class HomePrivacyResync {
    static let shared = HomePrivacyResync()

    private let log = Logger(subsystem: "com.onezee.TripTrack", category: "home-privacy")
    private var cancellables = Set<AnyCancellable>()

    /// `center` инжектируется ради тестов: пост в общий
    /// `NotificationCenter.default` разбудил бы продакшен-синглтоны поверх
    /// `PersistenceController.shared` — тот самый «хвост, роняющий чужой
    /// класс» из CLAUDE.md.
    init(center: NotificationCenter = .default) {
        center.publisher(for: .homePrivacyZoneChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.resendPublishedTrips() }
            .store(in: &cancellables)
    }

    /// Взвести подписку. Ничего не делает сверх `init` — но зовётся явно,
    /// чтобы дверь открывалась решением, а не случайным первым обращением к
    /// синглтону (тот же приём, что у `RevealedLayerSync.start()`).
    func start() {}

    /// Поставить каждую публичную поездку, которая УЖЕ лежит на сервере, в
    /// очередь на `.update`.
    ///
    /// Кого берём и почему именно этих:
    /// - `isPrivate == NO` — приватную чужие глаза не видят, и переотправлять
    ///   её ради обрезки нечего: её серверную копию обрежет первая же
    ///   настоящая правка, а гнать всю библиотеку в очередь при включённом
    ///   облаке значило бы залить сеть за один щелчок тумблера. Предикат тот
    ///   же, что у `AuthService.unpublishAllPublicTrips` и
    ///   `publishedTripCount`: «что видно чужим» в этом приложении
    ///   спрашивают одной строкой.
    /// - `serverCreatedAt != nil` — на сервере её ещё не было, значит и
    ///   исправлять нечего: первый её апсерт уедет обрезанным сам.
    /// - не черновик. Публичным черновик не бывает по построению
    ///   (`SyncEnqueuer.isDraftTrip` не пускает его на сервер ни при каком
    ///   облаке), но выборка не имеет права на это НАДЕЯТЬСЯ: одно правило
    ///   «черновик вне мира» стоит во всех мировых выборках сразу, и эта —
    ///   мировая.
    ///
    /// `pendingUpload` взводится тем же решателем, что у правки отметки и
    /// достройки дыры (`CoreDataTripRepository.flipsPendingUpload`): у
    /// публичной поездки он отвечает `true` всегда, но спрашивать надо общую
    /// дверь, а не выводить правило заново четвёртый раз.
    ///
    /// Возвращает число поставленных поездок — ради теста и лога; человеку
    /// это число нигде не показывается.
    @discardableResult
    func resendPublishedTrips() -> Int {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "isPrivate == NO AND serverCreatedAt != nil"),
            TripConfirmation.notDraftPredicate,
        ])
        guard let entities = try? context.fetch(request), !entities.isEmpty else { return 0 }

        let cloudOn = SettingsManager.shared.cloudSyncEnabled
        var ids: [UUID] = []
        for entity in entities {
            guard let id = entity.id else { continue }
            entity.lastModifiedAt = Date()
            if CoreDataTripRepository.flipsPendingUpload(
                isPrivate: entity.isPrivate, cloudSyncEnabled: cloudOn) {
                entity.syncStatus = SyncStatus.pendingUpload.rawValue
            }
            ids.append(id)
        }
        PersistenceController.shared.save()

        // Очередь FIFO с дедупликацией: повторная постановка той же поездки не
        // удваивает работу. `.update` уносит трек ЦЕЛИКОМ — сервер стирает и
        // переписывает точки на каждом апсерте, и это ровно то, что здесь
        // нужно: обрезанный список обязан ЗАМЕНИТЬ полный, а не дополнить его.
        for id in ids {
            SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: id, action: .update))
        }
        log.notice("privacy zone changed — requeued \(ids.count, privacy: .public) published trips")
        return ids.count
    }
}
