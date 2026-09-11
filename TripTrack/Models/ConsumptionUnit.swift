import Foundation

/// How fuel consumption is shown: litres per 100 km, or miles per gallon.
///
/// The two are not a relabelling of each other — they run in opposite
/// directions. 6 л/100 км is a frugal car; 6 mpg is a truck with a problem.
/// An earlier pass through this screen wrote "mpg" over the stored per-100
/// numbers and shipped a card that praised thirst, which is why the conversion
/// lives here, in one place, with tests, instead of at each call site.
///
/// Storage never changes: `Vehicle.cityConsumption` and `.highwayConsumption`
/// are always litres per 100 km. This type only decides what a person sees and
/// how what they type comes back.
enum ConsumptionUnit: String, CaseIterable, Identifiable {
    case per100
    case mpg

    var id: String { rawValue }

    static let storageKey = "consumptionUnit"

    /// US gallons: 100 × 3.785411784 L/gal ÷ 1.609344 km/mi.
    ///
    /// The app's `VolumeUnit.gallons` is the US gallon everywhere else, so the
    /// imperial 282.48 constant would silently disagree with the price field
    /// one section below.
    static let mpgConstant: Double = 235.214583

    /// Stored value → what to show.
    ///
    /// **`distance` — не украшение подписи, а множитель.** Сотня миль длиннее
    /// сотни километров ровно в 1.609344 раза, значит и литров на неё уходит
    /// во столько же больше: 8 л/100 км — это 12.9 л/100 миль. До 0.6.7 выбор
    /// миль менял ЗДЕСЬ только подпись, а число оставлял километровым — ровно
    /// та же поломка, ради которой этот тип и написан («shipped a card that
    /// praised thirst»), только с другой стороны дроби.
    ///
    /// У `mpg` параметр не работает и работать не должен: мили в этой единице
    /// уже есть, они в самом её названии. Умножить ещё раз — значит сделать
    /// из экономичной машины прожорливую второй раз за две версии.
    func display(fromPer100 value: Double, distance: DistanceUnit) -> Double {
        switch self {
        case .per100:
            return distance.consumptionPer100(fromPer100Km: value)
        case .mpg:
            // A car that burns nothing has no mpg to report — 0 in, 0 out,
            // rather than an infinity that formats as "inf".
            guard value > 0 else { return 0 }
            return Self.mpgConstant / value
        }
    }

    /// What someone typed → what to store. Хранится ВСЕГДА л/100 км.
    func toPer100(_ displayed: Double, distance: DistanceUnit) -> Double {
        switch self {
        case .per100:
            return distance.per100Km(fromConsumptionPer100: displayed)
        case .mpg:
            guard displayed > 0 else { return 0 }
            return Self.mpgConstant / displayed
        }
    }

    /// Потолок поля ввода — В ЕДИНИЦАХ ПОКАЗА.
    ///
    /// 50 л/100 км — абсурдная машина, 50 mpg — обычная; но и 50 л/100 МИЛЬ —
    /// тоже обычная (это 31 л/100 км). Потолок, заданный числом «50» в любой
    /// единице, отверг бы у мильного человека вполне нормальный расход, и он
    /// решил бы, что поле сломано.
    func inputCeiling(distance: DistanceUnit) -> Double {
        switch self {
        case .mpg:    return 250
        case .per100: return distance.consumptionPer100(fromPer100Km: 50)
        }
    }

    /// The short label the segmented control shows.
    func segmentLabel(_ lang: LanguageManager.Language) -> String {
        switch self {
        case .per100: return AppStrings.unitLPer100(lang)
        case .mpg:    return "mpg"
        }
    }

    /// The unit printed next to a value. Per-100 keeps deferring to the
    /// volume/distance settings — «л/100 км», "gal/100mi" — because that pair
    /// is a real, converted unit; mpg is its own thing and reads the same in
    /// both languages.
    func valueUnit(volumeRaw: String, distance: DistanceUnit, lng: LanguageManager.Language) -> String {
        switch self {
        case .per100:
            return GarageFormat.consumptionUnit(
                volumeRaw: volumeRaw, distance: distance, lng: lng)
        case .mpg:
            return "mpg"
        }
    }

    /// mpg values are whole-ish numbers people quote without decimals; per-100
    /// values live in the 4–15 range where the first decimal carries meaning.
    var fractionDigits: Int {
        self == .mpg ? 1 : 1
    }

    /// Current preference, for the non-SwiftUI call sites.
    static var current: ConsumptionUnit {
        ConsumptionUnit(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "")
            ?? .per100
    }

    // MARK: - Fuel price

    static let litresPerGallon: Double = 3.785411784

    /// Choosing mpg is choosing gallons — miles per gallon and roubles per
    /// litre are not a set of units anyone actually uses together. So the
    /// segment carries the volume unit with it, and the price row follows.
    var volumeUnit: VolumeUnit {
        self == .mpg ? .gallons : .liters
    }

    /// `Vehicle.fuelPrice` is stored PER LITRE, always — that is what the trip
    /// cost calculation multiplies litres by. The gallon setting used to only
    /// change the label next to the field, so «56 ₽/л» became «56 ₽/gal» on a
    /// tap and every trip's cost silently stayed litre-priced.
    func displayPrice(fromPerLitre value: Double) -> Double {
        self == .mpg ? value * Self.litresPerGallon : value
    }

    func priceToPerLitre(_ displayed: Double) -> Double {
        self == .mpg ? displayed / Self.litresPerGallon : displayed
    }
}
