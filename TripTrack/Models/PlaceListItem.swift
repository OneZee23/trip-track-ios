import Foundation

/// Строка списка «Мест» (S1): всё, что карточке нужно, посчитано один раз
/// вне `body`. «Обычно» — медиана ГЛАВНОГО направления (по числу проездов):
/// у дороги к морю оно и есть ответ; когда курсов нет — медиана по всем.
struct PlaceListItem: Identifiable, Equatable {
    let place: Place
    let stats: PlaceStats
    let usual: TimeInterval?
    var id: UUID { place.id }
    var isFirstTime: Bool { stats.isFirstTime }
    var isFrequentGuest: Bool { stats.isFrequentGuest }
    var lastAt: Date? { stats.lastAt }

    static func build(place: Place, passes: [PlacePass], now: Date = Date()) -> PlaceListItem {
        let stats = PlaceStats.build(from: passes, now: now)
        return PlaceListItem(place: place, stats: stats,
                             usual: stats.directions.first?.median ?? stats.medianElapsed)
    }

    /// Свежие сверху; без проездов — в конец, по имени: место без истории —
    /// ещё не история.
    static func sorted(_ items: [PlaceListItem]) -> [PlaceListItem] {
        items.sorted {
            switch ($0.lastAt, $1.lastAt) {
            case let (a?, b?): return a > b
            case (nil, nil): return ($0.place.name ?? "") < ($1.place.name ?? "")
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }
}
