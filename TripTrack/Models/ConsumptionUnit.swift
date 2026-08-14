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
    func display(fromPer100 value: Double) -> Double {
        switch self {
        case .per100:
            return value
        case .mpg:
            // A car that burns nothing has no mpg to report — 0 in, 0 out,
            // rather than an infinity that formats as "inf".
            guard value > 0 else { return 0 }
            return Self.mpgConstant / value
        }
    }

    /// What someone typed → what to store.
    func toPer100(_ displayed: Double) -> Double {
        switch self {
        case .per100:
            return displayed
        case .mpg:
            guard displayed > 0 else { return 0 }
            return Self.mpgConstant / displayed
        }
    }

    /// The short label the segmented control shows.
    func segmentLabel(_ lang: LanguageManager.Language) -> String {
        switch self {
        case .per100: return lang == .ru ? "л/100" : "L/100"
        case .mpg:    return "mpg"
        }
    }

    /// The unit printed next to a value. Per-100 keeps deferring to the
    /// volume/distance settings — «л/100 км», "gal/100mi" — because that pair
    /// is a real, converted unit; mpg is its own thing and reads the same in
    /// both languages.
    func valueUnit(volumeRaw: String, distanceRaw: String, isRu: Bool) -> String {
        switch self {
        case .per100:
            return GarageFormat.consumptionUnit(
                volumeRaw: volumeRaw, distanceRaw: distanceRaw, isRu: isRu)
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
