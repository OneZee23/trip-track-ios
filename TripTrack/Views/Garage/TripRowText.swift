import Foundation

/// Что написано в строке поездки внутри гаража.
///
/// Заведено отдельным типом, потому что первая версия списка сочиняла эти
/// строки на месте и в итоге не сообщала ничего: заголовок падал в «Не
/// указано» (подпись из паспорта машины, к поездке отношения не имеющая),
/// а под ним стоял регион — тот же самый у всех строк подряд, потому что
/// человек ездит по одному краю. Список из десяти «Не указано · Краснодар»
/// не отвечает ни на один вопрос, который к нему приходят задать.
///
/// Строка обязана отвечать на три: ЧТО, КОГДА и СКОЛЬКО. Отсюда лестница
/// заголовка (имя → регион → «Поездка»), время в подписи и километры справа.
enum TripRowText {

    /// Та же лестница, что на экране поездки (`TripDetailView.barTitle`):
    /// собственное имя, иначе регион, иначе родовое слово. Расходиться им
    /// нельзя — иначе одна поездка называется в списке одним, а внутри другим.
    static func title(_ t: Trip, _ l: LanguageManager.Language) -> String {
        if t.hasDisplayableName, let name = t.title, !name.isEmpty { return name }
        if let region = RegionDisplay.localized(t.region, language: l), !region.isEmpty {
            return region
        }
        return AppStrings.tripTitle(l)
    }

    /// «5 сент., 17:41 · 23 мин». Время дня здесь не украшение: в один день
    /// обычно две поездки — туда и обратно, — и без часов они неразличимы.
    /// Год приписывается только к чужому году, как принято в iOS.
    static func when(_ t: Trip, _ l: LanguageManager.Language) -> String {
        let cal = Calendar.current
        let thisYear = cal.component(.year, from: t.startDate) == cal.component(.year, from: Date())
        let stamp = formatter(l, withYear: !thisYear).string(from: t.startDate)
        let dur = t.formattedDurationHuman(l)
        return dur.isEmpty ? stamp : stamp + " · " + dur
    }

    /// Короткая поездка не должна показывать «0 км»: четыреста метров — это
    /// «0,4», а ноль читается как сломанная запись.
    static func km(_ t: Trip, _ l: LanguageManager.Language) -> String {
        let value = t.distanceKm < 10
            ? GarageFormat.fuel(t.distanceKm, lng: l)
            : GarageFormat.odometer(t.distanceKm, lng: l)
        return value + " " + AppStrings.km(l)
    }

    static func elevation(_ t: Trip, _ l: LanguageManager.Language) -> String {
        "↑ " + GarageFormat.odometer(t.elevation, lng: l) + " " + AppStrings.unitMeters(l)
    }

    // MARK: - Форматтеры

    /// `DateFormatter` дорог в постройке, а список прокручивают — поэтому по
    /// одному на язык, а не по одному на строку.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]

    private static func formatter(_ l: LanguageManager.Language,
                                 withYear: Bool) -> DateFormatter {
        let key = l.rawValue + (withYear ? "-y" : "")
        lock.lock()
        defer { lock.unlock() }
        if let f = cache[key] { return f }
        let f = DateFormatter()
        f.locale = l.locale
        f.setLocalizedDateFormatFromTemplate(withYear ? "dMMMyyyyHm" : "dMMMHm")
        cache[key] = f
        return f
    }
}
