import Foundation

/// «Как только маршрут построен и человек её не трогал — ставится
/// `suggestedDuration`» — решение владельца 20 сен, вынесено чистой функцией
/// ровно затем, чтобы его проверял тест, а не открытый лист на телефоне
/// (тот же довод, что у `AutoTripPolicy` и `JourneyEditSheet.startBounds`).
enum ManualTripDurationPolicy {
    /// `touched` — человек хоть раз подвинул длительность стрелкой ±.
    /// `nil` подсказки (маршрут ещё не посчитан) не трогает текущее значение.
    static func resolve(
        current: TimeInterval,
        suggested: TimeInterval?,
        touched: Bool,
        step: TimeInterval
    ) -> TimeInterval {
        guard !touched, let suggested, suggested > 0 else { return current }
        return (suggested / step).rounded() * step
    }
}
