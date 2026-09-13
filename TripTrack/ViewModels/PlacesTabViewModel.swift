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
        NotificationCenter.default.publisher(for: .placesChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
        manager.$places
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    func reload() {
        items = PlaceListItem.sorted(manager.places.map {
            PlaceListItem.build(place: $0, passes: manager.passes(for: $0.id))
        })
    }
}
