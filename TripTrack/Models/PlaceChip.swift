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

    /// «Здесь 11 раз · обычно 2:14» / «Первый раз здесь». Модель, а не вью —
    /// так текст проверяет тест (`TripMomentsTimeline.placeChipText` раньше
    /// жила во вью и была недоступна тестам).
    func text(_ lang: LanguageManager.Language) -> String {
        guard count > 1 else { return AppStrings.placeChipFirst(lang) }
        let here = AppStrings.placeHereTimes(lang, count: count)
        guard let usual else { return here }
        return "\(here) · \(AppStrings.placeChipUsually(lang, time: CheckpointReading.clock(usual, lang: lang)))"
    }
}
