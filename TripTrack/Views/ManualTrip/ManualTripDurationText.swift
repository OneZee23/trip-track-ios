import Foundation

/// «2 ч 30 мин» — печать длительности, общая для кнопки «Записать» и блока
/// «Когда»/«Машина», чтобы два места не разошлись в форматировании одного и
/// того же числа.
enum ManualTripDurationText {
    static func string(_ seconds: TimeInterval, lang: LanguageManager.Language) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let h = AppStrings.hoursUnitShort(lang)
        let m = AppStrings.minutesUnitShort(lang)
        if hours == 0 { return "\(minutes) \(m)" }
        if minutes == 0 { return "\(hours) \(h)" }
        return "\(hours) \(h) \(minutes) \(m)"
    }
}
