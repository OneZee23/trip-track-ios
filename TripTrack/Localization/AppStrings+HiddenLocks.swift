import Foundation

/// Замки, которые тянутся по маршруту в «Скрыть от других» (0.9.5). Ключи общие с Android:
/// его строки собираются из этих таблиц (`tools/strings/generate.py`).
extension AppStrings {
    static func hiddenDragHint(_ l: LanguageManager.Language) -> String { tr(l, "hiddenDragHint", ru: "Тяните замки по маршруту. Чтобы скрыть участок в середине, задержите палец на линии.", en: "Drag the locks along the route. To hide a part in the middle, press and hold on the line.") }
    static func hiddenHandleStartHidden(_ l: LanguageManager.Language, distance: String) -> String {
        tr(l, "hiddenHandleStartHidden", ru: "Скрыто начало {distance}", en: "Start hidden: {distance}")
            .replacingOccurrences(of: "{distance}", with: distance)
    }
    static func hiddenHandleEndHidden(_ l: LanguageManager.Language, distance: String) -> String {
        tr(l, "hiddenHandleEndHidden", ru: "Скрыт конец {distance}", en: "End hidden: {distance}")
            .replacingOccurrences(of: "{distance}", with: distance)
    }
    static func hiddenHandleStartVisible(_ l: LanguageManager.Language) -> String { tr(l, "hiddenHandleStartVisible", ru: "Начало видно", en: "Start is visible") }
    static func hiddenHandleEndVisible(_ l: LanguageManager.Language) -> String { tr(l, "hiddenHandleEndVisible", ru: "Конец виден", en: "End is visible") }
    static func hiddenHandleDragInward(_ l: LanguageManager.Language) -> String { tr(l, "hiddenHandleDragInward", ru: "Тяните по маршруту, чтобы скрыть", en: "Drag along the route to hide") }
    static func hiddenHandleParkingOnly(_ l: LanguageManager.Language) -> String { tr(l, "hiddenHandleParkingOnly", ru: "Скрыта только стоянка", en: "Only the parked time is hidden") }
    static func hiddenHandleBeforeDeparture(_ l: LanguageManager.Language, duration: String) -> String {
        tr(l, "hiddenHandleBeforeDeparture", ru: "{duration} до выезда", en: "{duration} before you set off")
            .replacingOccurrences(of: "{duration}", with: duration)
    }
    static func hiddenHandleAfterStop(_ l: LanguageManager.Language, duration: String) -> String {
        tr(l, "hiddenHandleAfterStop", ru: "{duration} после остановки", en: "{duration} after you stopped")
            .replacingOccurrences(of: "{duration}", with: duration)
    }
    static func hiddenHandleUntil(_ l: LanguageManager.Language, time: String) -> String {
        tr(l, "hiddenHandleUntil", ru: "до {time}", en: "until {time}")
            .replacingOccurrences(of: "{time}", with: time)
    }
    static func hiddenHandleFrom(_ l: LanguageManager.Language, time: String) -> String {
        tr(l, "hiddenHandleFrom", ru: "с {time}", en: "from {time}")
            .replacingOccurrences(of: "{time}", with: time)
    }
    static func hiddenSectionRemoved(_ l: LanguageManager.Language) -> String { tr(l, "hiddenSectionRemoved", ru: "Участок убран", en: "Section removed") }
    static func hiddenSummaryStartParking(_ l: LanguageManager.Language) -> String { tr(l, "hiddenSummaryStartParking", ru: "Стоянка в начале", en: "Parked time at the start") }
    static func hiddenSummaryEndParking(_ l: LanguageManager.Language) -> String { tr(l, "hiddenSummaryEndParking", ru: "Стоянка в конце", en: "Parked time at the end") }
    static func hiddenHandleMoveForward(_ l: LanguageManager.Language) -> String { tr(l, "hiddenHandleMoveForward", ru: "Сдвинуть вперёд по маршруту", en: "Move forward along the route") }
    static func hiddenHandleMoveBack(_ l: LanguageManager.Language) -> String { tr(l, "hiddenHandleMoveBack", ru: "Сдвинуть назад по маршруту", en: "Move back along the route") }
    static func hiddenHandleStartLabel(_ l: LanguageManager.Language) -> String { tr(l, "hiddenHandleStartLabel", ru: "Граница скрытого начала", en: "Hidden start boundary") }
    static func hiddenHandleEndLabel(_ l: LanguageManager.Language) -> String { tr(l, "hiddenHandleEndLabel", ru: "Граница скрытого конца", en: "Hidden end boundary") }
}
