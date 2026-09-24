import Foundation

/// Подтверждена ли поездка человеком (спека §3).
///
/// `draft` — поездка, которую начало само приложение в режиме «Напоминания»:
/// трек пишется, но в мир — атлас, места, награды, одометр, статистику,
/// путешествия, синк — она не выходит, пока человек не скажет «Моя».
/// `rawValue` — колонка `TripEntity.confirmation`, менять нельзя.
enum TripConfirmation: String, Codable {
    case confirmed
    case draft
}

/// Где поездка в достройке дыр (спека §2.3, §2.5).
///
/// `unchecked` — до 0.8.1 никто не смотрел; `pending` — есть прямая
/// достройка, дорогу ещё не спросили; `done` — всё, что можно было
/// достроить дорогой, достроено. `rawValue` — колонка
/// `TripEntity.roadFillState`, менять нельзя.
enum RoadFillState: String, Codable {
    case unchecked
    case pending
    case done
}

extension TripConfirmation {
    /// Черновик в мир не выходит (спека §3.2). Один предикат для всех
    /// «мировых» выборок поездок: `completedTripPredicate` репозитория и сырые
    /// выборки вне его. Пустая колонка — подтверждённая поездка: так читаются
    /// все поездки до 0.8.1.
    static let notDraftPredicate = NSPredicate(
        format: "confirmation == nil OR confirmation != %@", TripConfirmation.draft.rawValue)
    /// То же для выборок точек и отметок — через связь с поездкой.
    static let tripNotDraftPredicate = NSPredicate(
        format: "trip.confirmation == nil OR trip.confirmation != %@", TripConfirmation.draft.rawValue)
}
