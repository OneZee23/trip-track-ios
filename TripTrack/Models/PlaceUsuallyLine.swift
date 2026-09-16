import Foundation

/// Вторая строка карточки «Обычно занимает» — только то, что ДОБАВЛЯЕТ
/// знание к медиане, стоящей строкой выше.
///
/// До фикс-волны 0.7.0 здесь печаталось «1 ч 19 мин · 1 ч 19 мин · 1 проезд»:
/// лучшее и худшее время у одного проезда равны медиане по определению, и
/// человек читал одно и то же число трижды подряд. Правило теперь одно —
/// разброс показывается, только когда он ЕСТЬ:
///
/// - один проезд — «1 проезд», и всё;
/// - несколько, но напечатанные края совпали — тоже только счёт;
/// - края разошлись — «от 1 ч 10 мин до 1 ч 30 мин · 3 проезда».
///
/// Совпадение проверяется по НАПЕЧАТАННЫМ строкам, а не по секундам:
/// `CheckpointReading.clock` округляет до минут, и разница в сорок секунд
/// дала бы «от 1 ч 14 мин до 1 ч 14 мин» — ту же поломку, только с союзом.
///
/// Чистая функция — потому что проверить её можно только словами, а слова
/// зависят от языка и от числа (1/2/5 у русского считаются по-разному).
enum PlaceUsuallyLine {
    static func compose(
        count: Int,
        best: TimeInterval,
        worst: TimeInterval,
        lang: LanguageManager.Language
    ) -> String {
        let passes = "\(AppStrings.formattedCount(count, lang: lang)) \(AppStrings.nounPasses(lang, count))"
        let low = CheckpointReading.clock(min(best, worst), lang: lang)
        let high = CheckpointReading.clock(max(best, worst), lang: lang)
        guard count > 1, low != high else { return passes }
        return "\(AppStrings.placeUsuallyRange(lang, min: low, max: high)) · \(passes)"
    }
}
