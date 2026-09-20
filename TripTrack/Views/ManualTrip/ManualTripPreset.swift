import Foundation
import CoreLocation

/// Что лист «Вписать поездку» открывает УЖЕ заполненным — пустая дата с
/// календаря, или зеркало только что созданной поездки для «Добавить
/// обратную дорогу».
///
/// Отдельный тип, а не набор параметров у `ManualTripSheet`: у пресета три
/// независимых источника (календарь, кнопка приветствия, тост после
/// создания), и разводить их по трём инициализаторам листа значило бы
/// плодить дублирующиеся параметры.
struct ManualTripPreset {
    var from: ManualTripPoint?
    var to: ManualTripPoint?
    var vehicleId: UUID?
    var startDate: Date?
    var duration: TimeInterval?

    /// Тап по пустому дню в `ProfileHistoryCalendar`: только дата, 09:00 по
    /// умолчанию (или «сейчас», если день сегодняшний и девять утра ещё не
    /// наступило).
    static func forDay(_ day: Date, now: Date = Date()) -> ManualTripPreset {
        ManualTripPreset(startDate: ManualTripDateDefaults.defaultStartDate(forDay: day, now: now))
    }

    /// «Добавить обратную дорогу»: точки поменяны местами, машина та же,
    /// старт — конец первой поездки плюс час, не позже «сейчас» (в будущее
    /// нельзя — то же правило, что у самой поездки). Длительность НЕ
    /// переносится: маршрут «туда» и «обратно» по разным дорогам не всегда
    /// занимает одно и то же время, и пересчёт от Apple здесь честнее.
    static func returnTrip(
        from: ManualTripPoint, to: ManualTripPoint,
        vehicleId: UUID?, firstTripEnd: Date, now: Date = Date()
    ) -> ManualTripPreset {
        ManualTripPreset(
            from: to, to: from, vehicleId: vehicleId,
            startDate: min(firstTripEnd.addingTimeInterval(3600), now)
        )
    }
}
