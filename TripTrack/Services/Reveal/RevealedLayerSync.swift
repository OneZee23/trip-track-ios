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
/// Сам разбор живёт в сторе (`reconcile()`): здесь только подписка и задача,
/// которую можно дождаться в тесте.
@MainActor
final class RevealedLayerSync {
    static let shared = RevealedLayerSync()

    private let store: RevealedLayerStore
    private var cancellables = Set<AnyCancellable>()
    private var task: Task<Void, Never>?

    init(store: RevealedLayerStore = .shared) {
        self.store = store
        NotificationCenter.default.publisher(for: .syncPullCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.task = Task { await self.store.reconcile() }
            }
            .store(in: &cancellables)
    }

    /// Взвести подписку. Ничего не делает сверх `init` — но зовётся явно,
    /// чтобы дверь открывалась решением, а не случайным первым обращением
    /// к синглтону.
    func start() {}

    /// Дождаться сверки, начатой пулом.
    func settle() async { await task?.value }
}
