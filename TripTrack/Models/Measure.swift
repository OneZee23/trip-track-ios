import Foundation

/// Единственный производитель строк расстояния, скорости и высоты.
///
/// До 0.6.7 таких мест было семь (`GarageFormat.odometer/fuel/oneDecimal`,
/// `TripDetailFormat.groupedNumber`, `CheckpointReading.kilometres`,
/// `AppStrings.groupedNumber`, голый `String(format: "%.1f")`), а правило «до
/// десяти — с десятыми» было независимо переписано ЧЕТЫРЕ раза. Пока единица
/// была одна, четыре копии давали одинаковый ответ; на второй единице они
/// разъезжаются, и побеждает та, которую позвали последней.
///
/// **Все параметры явные, у `unit` значения по умолчанию НЕТ.** Это и есть
/// рычаг всей версии: новое место показа не соберётся, не назвав единицу, —
/// и значит не сможет молча напечатать километры человеку, который выбрал
/// мили. Единицу берут из `@Environment(\.distanceUnit)` (экраны) или из
/// `DistanceUnit.current` (сервисы вне SwiftUI).
///
/// **Метры на входе, километры — только у одометра.** Хранение метрическое:
/// `Trip.distance` — метры, скорость — м/с. Единственный вход в километрах
/// назван вслух (`odometer(km:)`), потому что `Vehicle.odometerKm` в метры не
/// мигрирует: против него уже записаны уровни машин в базе.
///
/// **Разделитель и разряды — отсюда, а не с места вызова.** Внутри всегда
/// `AppStrings.decimalSeparator` и `AppStrings.groupedNumber`; поэтому
/// вызывающему нечего писать через `String(format:)`, а вместе с этим уходят
/// три живых бага локали (точка вместо запятой на немецком телефоне).
enum Measure {

    /// Сколько знаков показывать. Округление у каждой точки вызова остаётся
    /// сегодняшним — три стиля описывают то, что уже нарисовано, а не новую
    /// вёрстку.
    enum Style {
        /// Всегда одна десятая: карточки ленты, итог поездки, плитка
        /// «Дистанция», плашка REC, восстановление, постер.
        case tenths
        /// Целое с разрядами по языку: одометр, статистика, регионы,
        /// путешествия, профиль.
        case grouped
        /// Десятые ниже `unit.tenthsBelow`, дальше целое с разрядами:
        /// отметки, строка поездки в гараже, виджет, «дороги края».
        case adaptive
    }

    // MARK: - Расстояние

    /// «128 км» / «79 mi» — число и подпись, собранные вместе.
    ///
    /// Вместе, а не двумя вызовами: подпись склоняется по показанному числу
    /// («8,4 мили», но «5 миль»), и разлучить их — значит однажды сложить
    /// «5» с «мили».
    static func distance(
        metres: Double,
        unit: DistanceUnit,
        lang: LanguageManager.Language,
        style: Style = .adaptive
    ) -> String {
        let shown = number(unit.distance(fromMetres: metres), style: style, unit: unit, lang: lang)
        return label(
            shown,
            AppStrings.unitDistanceShort(
                lang, unit: unit, value: shown.value, fractionDigits: shown.fractionDigits)
        )
    }

    /// Только число — для вёрстки, где подпись стоит отдельной строкой или
    /// своим шрифтом. Подпись к нему берут у `AppStrings.unitDistanceShort`,
    /// иначе форма разойдётся с числом.
    static func distanceValue(
        metres: Double,
        unit: DistanceUnit,
        lang: LanguageManager.Language,
        style: Style = .adaptive
    ) -> String {
        number(unit.distance(fromMetres: metres), style: style, unit: unit, lang: lang).text
    }

    /// «38 420 км» — пробег машины. Единственная дверь, куда километры входят
    /// как километры: `Vehicle.odometerKm` хранится в них и в 0.6.7 в метры не
    /// мигрирует.
    static func odometer(
        km: Double,
        unit: DistanceUnit,
        lang: LanguageManager.Language
    ) -> String {
        distance(metres: km * 1000, unit: unit, lang: lang, style: .grouped)
    }

    // MARK: - Скорость

    /// «68 км/ч» / «42 mph». На входе метры в секунду — то, чем скорость
    /// приезжает от CoreLocation и живёт в треке.
    static func speed(
        ms: Double,
        unit: DistanceUnit,
        lang: LanguageManager.Language
    ) -> String {
        let shown = number(unit.speed(fromMetresPerSecond: ms), style: .grouped, unit: unit, lang: lang)
        return label(shown, AppStrings.unitSpeedShort(lang, unit: unit))
    }

    static func speedValue(
        ms: Double,
        unit: DistanceUnit,
        lang: LanguageManager.Language
    ) -> String {
        number(unit.speed(fromMetresPerSecond: ms), style: .grouped, unit: unit, lang: lang).text
    }

    // MARK: - Высота

    /// «640 м» / «2 100 ft». Отдельно от `odometer` НАРОЧНО: высота сегодня
    /// форматируется функцией про пробег, и встроенная в ту конверсия увезла
    /// бы метры в мили ×0.621 молча.
    static func elevation(
        metres: Double,
        unit: DistanceUnit,
        lang: LanguageManager.Language
    ) -> String {
        let shown = number(unit.elevation(fromMetres: metres), style: .grouped, unit: unit, lang: lang)
        return label(
            shown,
            AppStrings.unitElevationShort(
                lang, unit: unit, value: shown.value, fractionDigits: shown.fractionDigits)
        )
    }

    static func elevationValue(
        metres: Double,
        unit: DistanceUnit,
        lang: LanguageManager.Language
    ) -> String {
        number(unit.elevation(fromMetres: metres), style: .grouped, unit: unit, lang: lang).text
    }

    // MARK: - Числа

    /// Напечатанное число вместе с тем, что о нём нужно знать подписи: каким
    /// оно вышло после округления и сколько десятых у него ВИДНО. Второе —
    /// не то же самое, что первое: «2,0» и «2» это одно значение и две разные
    /// формы слова после него.
    private struct Shown {
        let text: String
        let value: Double
        let fractionDigits: Int
    }

    private static func number(
        _ raw: Double,
        style: Style,
        unit: DistanceUnit,
        lang: LanguageManager.Language
    ) -> Shown {
        // NaN и бесконечность приезжают из сломанного GPS-семпла и битой
        // записи, а `Int(nan)` — это не «0», это падение процесса. Форматтер
        // не имеет права ронять экран.
        let value = raw.isFinite ? raw : 0
        switch style {
        case .tenths:
            return tenths(value, lang)
        case .grouped:
            return grouped(value, lang)
        case .adaptive:
            return value < unit.tenthsBelow ? tenths(value, lang) : grouped(value, lang)
        }
    }

    private static func tenths(_ value: Double, _ lang: LanguageManager.Language) -> Shown {
        let rounded = (value * 10).rounded() / 10
        // `%.1f` пишет точку в любой локали — разделитель подставляется
        // языком, а не системой: язык приложения и язык телефона у нас
        // расходятся законно.
        let text = String(format: "%.1f", rounded)
            .replacingOccurrences(of: ".", with: AppStrings.decimalSeparator(lang))
        return Shown(text: text, value: rounded, fractionDigits: 1)
    }

    private static func grouped(_ value: Double, _ lang: LanguageManager.Language) -> Shown {
        let rounded = value.rounded()
        // Ограничение — не про наши расстояния, а про то, что `Int(_:)` от
        // числа за пределами Int падает, а не насыщается.
        let clamped = min(max(rounded, -1e15), 1e15)
        return Shown(
            text: AppStrings.groupedNumber(Int(clamped), lang),
            value: clamped,
            fractionDigits: 0
        )
    }

    /// Число и подпись через обычный пробел — ровно так их сегодня и склеивают
    /// на экранах. Неразрывным здесь пробел не делаем: он уже стоит ВНУТРИ
    /// числа (в разрядах), и «12 000 км» с двумя разными пробелами выглядит
    /// одинаково, а сравнивается по-разному.
    private static func label(_ shown: Shown, _ unit: String) -> String {
        "\(shown.text) \(unit)"
    }
}
