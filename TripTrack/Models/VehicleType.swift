import Foundation

/// What kind of thing is in the garage.
///
/// The garage used to hold cars only, and the UI said so — «автомобиль»
/// everywhere. It holds transport now, and the type decides which parts of the
/// vehicle form even make sense: a bicycle has no plate, burns no fuel and
/// cannot pair with a car stereo, so those sections are absent rather than
/// present-and-empty.
///
/// Raw values are persisted (CoreData `vehicleType`, sync payload) — renaming a
/// case renames the stored value, so add cases, never rewrite them. The list is
/// deliberately open-ended: the canon calls the type selector "расширяемый".
enum VehicleType: String, Codable, CaseIterable, Identifiable, Sendable {
    case car
    case moto
    case moped
    case bicycle

    var id: String { rawValue }

    /// Falls back to `.car` for values written by older builds (where the
    /// column did not exist) and for anything unrecognised.
    init(storage: String?) {
        self = storage.flatMap(VehicleType.init(rawValue:)) ?? .car
    }

    var icon: String {
        switch self {
        case .car:     return "car.fill"
        case .moto:    return "figure.outdoor.cycle"
        case .moped:   return "scooter"
        case .bicycle: return "bicycle"
        }
    }

    func label(_ lang: LanguageManager.Language) -> String {
        switch self {
        case .car:     return AppStrings.vehicleTypeCar(lang)
        case .moto:    return AppStrings.vehicleTypeMoto(lang)
        case .moped:   return AppStrings.vehicleTypeMoped(lang)
        case .bicycle: return AppStrings.vehicleTypeBike(lang)
        }
    }

    // MARK: - What this type can carry

    /// Mopeds and bicycles carry no registration plate in most of the world,
    /// so the field is hidden rather than optional-and-awkward.
    var hasPlate: Bool {
        self == .car || self == .moto
    }

    /// A bicycle burns nothing — consumption and fuel price are meaningless.
    var burnsFuel: Bool {
        self != .bicycle
    }

    /// Auto-record keys off a Bluetooth car stereo, which only cars and
    /// motorcycles have.
    var supportsAutoRecord: Bool {
        self == .car || self == .moto
    }
}
