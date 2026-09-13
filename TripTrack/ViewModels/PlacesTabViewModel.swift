import Foundation
import Combine

/// Список вкладки «Места»: считается на загрузке и по `.placesChanged`,
/// а не в `body` — `passes(for:)` ходит в CoreData на каждое место.
@MainActor
final class PlacesTabViewModel: ObservableObject {
    @Published private(set) var items: [PlaceListItem] = []
    private let manager: PlaceManager
    private var cancellables = Set<AnyCancellable>()

    init(manager: PlaceManager = .shared) {
        self.manager = manager
        // Одна подписка: все пути, что меняют места (rename/delete/adoptName/
        // reconcile/process), постят `.placesChanged` сами — вторая, на
        // `$places`, значила бы два reload() на одну и ту же правку.
        NotificationCenter.default.publisher(for: .placesChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
        // Без этого первый кадр вкладки рисует пустую сцену «Мест пока нет»,
        // которую тут же сменяет список: `items` иначе заполняется только
        // асинхронно, по подписке.
        reload()
    }

    func reload() {
        items = PlaceListItem.sorted(manager.places.map {
            PlaceListItem.build(place: $0, passes: manager.passes(for: $0.id))
        })
    }
}
