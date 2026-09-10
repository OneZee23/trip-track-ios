import Foundation
import CoreLocation

/// «1:30 · 128 км» — то, ради чего ставится отметка.
///
/// Одна функция на три места, где это число показывается: карточка под
/// картой, подтверждение под пальцем и подпись маркера на самой карте. Три
/// копии форматирования разошлись бы на первой же правке — в одном месте
/// запятая, в другом точка.
///
/// Время впереди, потому что спрашивают обычно про него: «до моря — за
/// сколько?», и только потом «а сколько это километров».
///
/// Само расстояние с 0.6.7 считает и подписывает `Measure` — своя копия
/// правила «до десяти показываем десятые» жила здесь ровно до тех пор, пока
/// единица была одна.
enum CheckpointReading {
    static func text(
        elapsed: TimeInterval,
        metres: Double,
        unit: DistanceUnit,
        lang: LanguageManager.Language
    ) -> String {
        let distance = Measure.distance(metres: max(0, metres), unit: unit, lang: lang)
        return "\(clock(elapsed, lang: lang)) · \(distance)"
    }

    /// «1 ч 19 мин», «2 ч», «48 мин» — словами, как везде в приложении.
    ///
    /// Было «1:19», и это читалось как время на часах, а не как «сколько
    /// ехали». Единицы берём те же, что у карточек ленты («23 ч 7 мин»),
    /// чтобы поездка и отметка говорили одним языком.
    static func clock(_ elapsed: TimeInterval, lang: LanguageManager.Language) -> String {
        let total = max(0, Int(elapsed))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let h = AppStrings.hoursUnitShort(lang)
        let m = AppStrings.minutesUnitShort(lang)
        switch (hours, minutes) {
        case (0, _): return "\(minutes) \(m)"
        case (_, 0): return "\(hours) \(h)"
        default:     return "\(hours) \(h) \(minutes) \(m)"
        }
    }

}

extension Notification.Name {
    /// Отметки поездки изменились не с экрана — например, дозрело имя из
    /// геокодера. Экран поездки перечитывает список.
    static let tripCheckpointsChanged = Notification.Name("tripCheckpointsChanged")
}
