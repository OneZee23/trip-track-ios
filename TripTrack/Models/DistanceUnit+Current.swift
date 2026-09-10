import Foundation

/// Половина `DistanceUnit`, которой нет в виджете — и не должно быть.
///
/// Сам тип живёт в `TripTrackShared`, потому что арифметика обязана быть одна
/// на оба процесса. А вот ОТКУДА берётся выбор, у процессов разное: у
/// расширения свой контейнер `UserDefaults`, и `current` там вернула бы
/// километры навсегда и молча — на локскрине мили, в приложении километры, и
/// ни одной ошибки нигде. Поэтому чтение выбора и локализованное имя живут в
/// таргете приложения: пусть виджет физически не сможет их позвать.
///
/// Виджету единица приезжает полем `ContentState.distanceUnit` вместе с
/// остальным состоянием активности (шаг 6), тем же путём, что и язык.
extension DistanceUnit {

    /// Текущий выбор человека — для тех, кто вне SwiftUI: `NotificationManager`,
    /// `LiveActivityManager`, `AutoTripService`, `MapViewModel`. Ровно как
    /// `ConsumptionUnit.current` сегодня.
    ///
    /// Читать СВЕЖО на каждом вызове, не запоминать в поле: настройка меняется
    /// посреди сессии — и руками на экране, и пулом со второго телефона, — а
    /// сервис с запомненной единицей продолжит показывать прежнюю до
    /// перезапуска. Экраны SwiftUI берут её не отсюда, а из
    /// `@Environment(\.distanceUnit)`, чтобы перерисовываться на смене.
    ///
    /// Нераспознанное значение (чужой клиент, будущая версия) читается как
    /// километры, а не как пустота.
    static var current: DistanceUnit {
        DistanceUnit(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .km
    }

    /// Имя единицы в пикере «Единицы» — словом и на языке приложения.
    ///
    /// Не путать с подписью у числа: там «км»/«mi»/«миль», и её собирает
    /// `AppStrings.unitDistanceShort`, потому что подпись склоняется, а имя в
    /// списке — нет.
    func labelFull(_ lang: LanguageManager.Language) -> String {
        switch self {
        case .km: return AppStrings.tr(lang, "unitKilometersFull", ru: "Километры", en: "Kilometers")
        case .miles: return AppStrings.tr(lang, "unitMilesFull", ru: "Мили", en: "Miles")
        }
    }
}
