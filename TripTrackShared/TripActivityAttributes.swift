import ActivityKit
import Foundation

struct TripActivityAttributes: ActivityAttributes {
    /// Static data — set once when the activity starts.
    ///
    /// Та же мина, что этажом ниже у `ContentState`, только заряженная на
    /// будущее: эти четыре поля тоже декодируются у активности, пережившей
    /// обновление, и тоже синтезированным `Decodable`, который на пропущенном
    /// ключе бросает `keyNotFound`, а не берёт значение по умолчанию. Сегодня
    /// это безопасно ровно потому, что все четыре поля существуют с первой
    /// версии. **Пятое поле обязано приехать сюда с `decodeIfPresent` и
    /// ручным `init(from:)` в расширении** — иначе карточка умрёт посреди
    /// поездки у всех, кто обновился на ходу, и увидит это только владелец
    /// телефона, а не сборка.
    var tripId: UUID
    var startDate: Date
    var vehicleName: String
    var vehicleAvatar: String  // "pixel_car_orange" for image, or emoji like "🚗"

    struct ContentState: Codable, Hashable {
        /// Провод МЕТРИЧЕСКИЙ и таким останется: километры и километры в час.
        ///
        /// Переименовать эти два поля нельзя никогда. Активность, начатая
        /// старым бинарником, переживает обновление приложения, и её состояние
        /// декодируется уже НОВЫМ типом — переименованное поле не найдётся, и
        /// карточка умрёт посреди поездки. Что рисовать, говорит отдельное
        /// поле `distanceUnit`; переводит виджет, общим `DistanceUnit`.
        var speedKmh: Double
        var distanceKm: Double
        var isPaused: Bool
        var pausedDuration: TimeInterval
        var elapsedAtPause: TimeInterval?
        var isFinished: Bool = false
        var finalDuration: String?
        var averageSpeedKmh: Double?
        /// Dynamic — updates when user switches language in app
        var language: String = "en"
        /// Dynamic — follows map dark mode (sun-based)
        var isDarkMode: Bool = false
        /// Сколько отметок поставлено за эту поездку.
        ///
        /// Нужно ради отклика: кнопка на Live Activity срабатывает молча, и без
        /// растущего числа нажатие неотличимо от промаха — а промахнуться за
        /// рулём легко.
        var checkpointCount: Int = 0
        /// В чём ПОКАЗЫВАТЬ расстояние и скорость — `DistanceUnit.rawValue`.
        ///
        /// Строкой, а не самим enum'ом: `Codable` у enum'а с сырым значением
        /// падает на незнакомой строке, а сюда однажды приедет состояние,
        /// записанное версией, которая знает единицу, которой не знаем мы.
        /// Строка декодируется всегда, а неизвестное значение читается как
        /// километры — ровно так же, как читается неизвестный код языка.
        var distanceUnit: String = "km"
    }
}

// MARK: - Декодирование

/// Пропущенный ключ — это НЕ значение по умолчанию.
///
/// Синтезированный Swift'ом `Decodable` не смотрит на `= false` и `= "en"` в
/// объявлении: он зовёт `decode(_:forKey:)` и бросает `keyNotFound`. То есть
/// каждое поле, дописанное в `ContentState` за время жизни проекта
/// (`isFinished`, `language`, `isDarkMode`, `checkpointCount`, а теперь и
/// `distanceUnit`), ломало декодирование активности, начатой предыдущей
/// версией и пережившей обновление, — и ломало молча, потому что видно это
/// только на устройстве, где запись шла через апдейт из App Store.
///
/// Поэтому ручной `init(from:)` с `decodeIfPresent`. Он живёт в РАСШИРЕНИИ, а
/// не в теле структуры: инициализатор в теле отменил бы почленный, которым
/// `LiveActivityManager` собирает состояние в четырёх местах.
///
/// Обязательными остаются ровно те пять полей, что были у самой первой
/// версии, — без них рисовать нечего.
extension TripActivityAttributes.ContentState {
    enum CodingKeys: String, CodingKey {
        case speedKmh, distanceKm, isPaused, pausedDuration, elapsedAtPause
        case isFinished, finalDuration, averageSpeedKmh
        case language, isDarkMode, checkpointCount, distanceUnit
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speedKmh = try c.decode(Double.self, forKey: .speedKmh)
        distanceKm = try c.decode(Double.self, forKey: .distanceKm)
        isPaused = try c.decode(Bool.self, forKey: .isPaused)
        pausedDuration = try c.decode(TimeInterval.self, forKey: .pausedDuration)
        elapsedAtPause = try c.decodeIfPresent(TimeInterval.self, forKey: .elapsedAtPause)
        isFinished = try c.decodeIfPresent(Bool.self, forKey: .isFinished) ?? false
        finalDuration = try c.decodeIfPresent(String.self, forKey: .finalDuration)
        averageSpeedKmh = try c.decodeIfPresent(Double.self, forKey: .averageSpeedKmh)
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "en"
        isDarkMode = try c.decodeIfPresent(Bool.self, forKey: .isDarkMode) ?? false
        checkpointCount = try c.decodeIfPresent(Int.self, forKey: .checkpointCount) ?? 0
        distanceUnit = try c.decodeIfPresent(String.self, forKey: .distanceUnit)
            ?? DistanceUnit.km.rawValue
    }

    /// В чём рисовать. Незнакомая строка читается как километры — то же
    /// правило, что у языка: показать не то лучше, чем не показать ничего.
    var shownUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnit) ?? .km
    }
}
