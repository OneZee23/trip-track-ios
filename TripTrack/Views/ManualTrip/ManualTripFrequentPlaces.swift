import Foundation

/// Три самых частых места для чипов над точками листа — чистая функция от
/// уже посчитанных проездов, а не поход в `PlaceManager` внутри `body`
/// (тот же довод, что у `PlacesTabViewModel`).
enum ManualTripFrequentPlaces {
    /// `passCount` — уже посчитанное число проездов на место (`PlaceManager
    /// .passCount(for:)`), а не повторный счёт здесь: считать дважды —
    /// значит однажды разойтись с тем, что показывает экран места.
    static func top(_ places: [Place], passCount: (UUID) -> Int, limit: Int = 3) -> [Place] {
        places
            .map { ($0, passCount($0.id)) }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                lhs.1 != rhs.1 ? lhs.1 > rhs.1 : lhs.0.createdAt > rhs.0.createdAt
            }
            .prefix(limit)
            .map(\.0)
    }
}
