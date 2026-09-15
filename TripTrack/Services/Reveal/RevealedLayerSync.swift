import Foundation
import Combine

/// Дверь пула в открытый мир.
///
/// Писали в `RevealedLayerStore` ровно двое: финиш своей поездки и разовая
/// сборка после обновления. Поездка, приехавшая `/sync/pull` — со второго
/// телефона, после переустановки, после восстановления, — не проходила ни
/// через одну, и «Атлас» оставался сплошной мглой при полной библиотеке.
/// Тот же вопрос `PlaceManager` решает подпиской на `.syncPullCompleted`
/// (`PlaceManager.swift`), и здесь она зеркальная.
///
/// Порядок запуска гарантировал промах сам по себе: миграции (и сборка в них)
/// идут из `MapViewModel.init`, а первый пул — по `didBecomeActive`, то есть
/// ПОСЛЕ. Поэтому подписка взводится в `init` менеджера записи, до первого
/// пула, а не откладывается в задачу миграций.
///
/// Разбирается РОВНО то, что привёз пул: список применённых id едет в
/// `userInfo` уведомления (`SyncPullNotification.appliedTripIds`). Отметки по
/// времени здесь нет и быть не может — см. `RevealedLayerStore.ReconcileRequest`.
/// Уведомление БЕЗ ключа (чужой постер, тест) — «неизвестно», и стоит одного
/// полного прохода: он идемпотентен, просто длиннее.
///
/// Сам разбор живёт в сторе (`reconcile(_:)`): здесь только подписка и задача,
/// которую можно дождаться в тесте.
@MainActor
final class RevealedLayerSync {
    static let shared = RevealedLayerSync()

    private let store: RevealedLayerStore
    private var cancellables = Set<AnyCancellable>()
    private var task: Task<Void, Never>?

    /// `center` инжектируется ради тестов: пост в общий
    /// `NotificationCenter.default` разбудил бы продакшен-синглтоны поверх
    /// `PersistenceController.shared` — тот самый «хвост, роняющий чужой класс».
    init(store: RevealedLayerStore = .shared, center: NotificationCenter = .default) {
        self.store = store
        center.publisher(for: .syncPullCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                let request = Self.request(from: note)
                self.task = Task { await self.store.reconcile(request) }
            }
            .store(in: &cancellables)
    }

    /// Что просить у стора по этому уведомлению. Чистая функция: контракт
    /// «нет ключа — полный проход, пустой список — ничего» держит тест.
    static func request(from note: Notification) -> RevealedLayerStore.ReconcileRequest {
        guard let ids = note.userInfo?[SyncPullNotification.appliedTripIds] as? [UUID] else {
            return .full
        }
        return .ids(Set(ids))
    }

    /// Взвести подписку. Ничего не делает сверх `init` — но зовётся явно,
    /// чтобы дверь открывалась решением, а не случайным первым обращением
    /// к синглтону.
    func start() {}

    /// Дождаться сверки, начатой пулом.
    func settle() async { await task?.value }
}
