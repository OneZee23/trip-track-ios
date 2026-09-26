import Foundation
import CoreLocation
import MapKit

/// Место на карте «Атласа» (макет «Места» 0.8.1, S8).
///
/// Отдельный тип от `PlacePin` вкладки «Места»: у той булавки нет ни периода,
/// ни подписи под именем, а тащить их туда значило бы завести на вкладке поле,
/// которое там всегда `true`.
struct AtlasPlacePin: Identifiable, Equatable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let name: String?
    /// Последний проезд ВНУТРИ периода, если место в него попало, иначе
    /// последний вообще: подпись под именем отвечает на «когда я тут был», и
    /// у места вне периода честный ответ — его собственная дата.
    let lastAt: Date?
    let passCount: Int
    /// Медиана «от старта поездки» — вторая строка карточки при нажатии.
    let usual: TimeInterval?
    /// Хоть один проезд внутри выбранного окна. Без периода — все места свои.
    let inPeriod: Bool

    static func == (a: AtlasPlacePin, b: AtlasPlacePin) -> Bool {
        a.id == b.id && a.name == b.name && a.lastAt == b.lastAt && a.passCount == b.passCount
            && a.inPeriod == b.inPeriod
            && a.coordinate.latitude == b.coordinate.latitude
            && a.coordinate.longitude == b.coordinate.longitude
    }
}

enum AtlasPlaces {

    /// Место с уже поднятыми датами проездов. Даты поднимаются ОДИН раз на
    /// смену данных, а не на каждую смену периода: `passes(for:)` ходит в
    /// CoreData на каждое место, а период человек крутит пальцем.
    struct Seed: Equatable {
        let id: UUID
        let coordinate: CLLocationCoordinate2D
        let name: String?
        let usual: TimeInterval?
        /// Все проезды места, в любом порядке.
        let passDates: [Date]

        static func == (a: Seed, b: Seed) -> Bool {
            a.id == b.id && a.name == b.name && a.usual == b.usual && a.passDates == b.passDates
                && a.coordinate.latitude == b.coordinate.latitude
                && a.coordinate.longitude == b.coordinate.longitude
        }
    }

    /// Булавки под выбранный период.
    ///
    /// «В периоде» решает ПРОЕЗД, а не диапазон «первый…последний»: место, где
    /// были в январе и в декабре, не становится июньским оттого, что июнь
    /// лежит между этими датами.
    static func build(seeds: [Seed], period: AtlasPeriod,
                      now: Date = Date(), calendar: Calendar = .current) -> [AtlasPlacePin] {
        let window = period.interval(now: now, calendar: calendar)
        return seeds.map { seed in
            let inside = window.map { w in seed.passDates.filter { w.contains($0) } } ?? seed.passDates
            let hasWindow = window != nil
            let inPeriod = hasWindow ? !inside.isEmpty : true
            return AtlasPlacePin(
                id: seed.id,
                coordinate: seed.coordinate,
                name: seed.name,
                // Место в периоде подписывается своим проездом ВНУТРИ окна —
                // иначе под булавкой «в периоде» стояла бы дата снаружи него.
                lastAt: (inPeriod ? inside : seed.passDates).max(),
                passCount: seed.passDates.count,
                usual: seed.usual,
                inPeriod: inPeriod)
        }
        // Свежие первыми — так же, как список вкладки «Места»: при споре за
        // пиксель побеждает та булавка, которую добавили раньше.
        .sorted { ($0.lastAt ?? .distantPast) > ($1.lastAt ?? .distantPast) }
    }

    /// «3 места из 5 в периоде». Без периода строка не нужна вовсе — все свои.
    static func inPeriodCount(_ pins: [AtlasPlacePin]) -> Int {
        pins.filter(\.inPeriod).count
    }
}

/// Аннотация своего места на карте «Атласа».
///
/// Своя, а не `PlaceAnnotation` вкладки «Места»: у той нет ни периода, ни
/// подписи, а вид (`PlacePinView`) переиспользуется как есть — он про то, КАК
/// нарисовать булавку, и ничего не знает про то, откуда она взялась.
final class AtlasPlaceAnnotation: NSObject, MKAnnotation {
    let pin: AtlasPlacePin
    /// Дата последнего проезда, уже напечатанная: язык решает не карта.
    let dateText: String?
    /// Имя безымянного места — тоже готовой строкой.
    let unnamed: String

    var coordinate: CLLocationCoordinate2D { pin.coordinate }

    private static let dayMonth = LocalizedDateFormatter.templates("dMMM")

    init(pin: AtlasPlacePin, language: LanguageManager.Language) {
        self.pin = pin
        self.dateText = pin.lastAt.flatMap { Self.dayMonth[language]?.string(from: $0) }
        self.unnamed = AppStrings.placeUnnamed(language)
        super.init()
    }
}
