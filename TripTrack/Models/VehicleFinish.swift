import Foundation

enum VehicleFinish: String, CaseIterable, Identifiable {
    case gloss, matte, pearl, chrome

    var id: String { rawValue }
    static let availableFinishes: [VehicleFinish] = [.gloss, .matte]
    var isPlus: Bool { self != .gloss }

    static func parse(_ raw: String?) -> VehicleFinish? {
        raw.flatMap(Self.init(rawValue:))
    }

    static func effective(_ raw: String?, isPlus: Bool) -> VehicleFinish {
        let finish = parse(raw) ?? .gloss
        return finish.isPlus && !isPlus ? .gloss : finish
    }

    func label(_ l: LanguageManager.Language) -> String {
        switch self {
        case .gloss: return AppStrings.vehicleFinishGloss(l)
        case .matte: return AppStrings.vehicleFinishMatte(l)
        case .pearl: return AppStrings.vehicleFinishPearl(l)
        case .chrome: return AppStrings.vehicleFinishChrome(l)
        }
    }
}
