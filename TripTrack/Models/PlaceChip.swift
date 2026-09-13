import Foundation

/// Чип у отметки в «Моментах» (S4): «Здесь 11 раз · обычно 2:14». Один проезд
/// — «Первый раз здесь» без «обычно»: одно число — не «обычно».
struct PlaceChip: Equatable {
    let placeId: UUID
    let count: Int
    let usual: TimeInterval?

    static func build(placeId: UUID, stats: PlaceStats) -> PlaceChip {
        PlaceChip(placeId: placeId, count: stats.passCount,
                  usual: stats.passCount > 1 ? (stats.directions.first?.median ?? stats.medianElapsed) : nil)
    }
}
