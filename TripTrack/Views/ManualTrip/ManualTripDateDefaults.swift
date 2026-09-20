import Foundation

/// Даты листа «Вписать поездку»: чипы «Сегодня»/«Вчера» и границы пикера.
///
/// Чистые функции — тот же довод, что у `JourneyEditSheet.startBounds`
/// (CLAUDE.md, «Ловушки»): `ClosedRange` с перевёрнутыми концами роняет
/// процесс, а не отдаёт пустоту, поэтому границы обязаны собираться так,
/// чтобы перевернуть их было нельзя, и это обязан держать тест, а не
/// открытый экран на телефоне.
enum ManualTripDateDefaults {
    /// Время старта по умолчанию для чипа «Сегодня»/«Вчера» — 09:00
    /// выбранного дня, но не позже «сейчас»: в будущее уходить нельзя.
    static func defaultStartDate(
        forDay day: Date, now: Date = Date(), calendar: Calendar = .current
    ) -> Date {
        let nineAM = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        return min(nineAM, now)
    }

    /// Границы `DatePicker`. Верхняя — не меньше уже выбранного значения,
    /// нижняя — не больше него: перевернуть `a...b` этой парой нельзя по
    /// построению, что бы ни лежало в `current`.
    static func bounds(
        for current: Date, now: Date = Date(), calendar: Calendar = .current
    ) -> ClosedRange<Date> {
        let earliest = calendar.date(byAdding: .year, value: -20, to: now) ?? now
        return min(earliest, current)...max(now, current)
    }
}
