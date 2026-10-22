import Foundation

actor CarCatalog {
    static let shared = CarCatalog()
    private var loaded: Document?

    struct Document: Decodable {
        let schema: Int
        let makes: [Make]
    }

    struct Make: Decodable {
        let id: String
        let name: String
        let nameRu: String?
        let aliases: [String]?
        let models: [Model]
    }

    struct Model: Decodable {
        let id: String
        let name: String
        let aliases: [String]?
        let generations: [Generation]
    }

    struct Generation: Decodable {
        let id: String
        let name: String
        let yearStart: Int?
        let yearEnd: Int?
        let bodies: [String]?
        let variants: [Variant]
    }

    struct Variant: Decodable, Equatable {
        let id: String
        let label: String?
        let fuel: String?
        let displacementCc: Double?
        let powerHp: Int?
        let torqueNm: Double?
        let transmission: String?
        let gears: Int?
        let drivetrain: String?
        let zeroToHundredS: Double?
        let topSpeedKmh: Double?
        let curbWeightKg: Double?
        let fuelCombinedL100: Double?
        let electricRangeKm: Double?
        let batteryKwh: Double?
        let yearStart: Int?
        let yearEnd: Int?

        func specLine(_ l: LanguageManager.Language) -> String? {
            var engine: [String] = []
            if let cc = displacementCc, cc > 0 { engine.append(UnitNumber.tenths(cc / 1000, code: l.rawValue)) }
            if let hp = powerHp, hp > 0 { engine.append(AppStrings.garagePower(l, value: String(hp))) }
            var parts: [String] = []
            if !engine.isEmpty { parts.append(engine.joined(separator: " ")) }
            if let transmission, ["manual", "automatic", "cvt", "amt", "dct"].contains(transmission) {
                parts.append(AppStrings.garageGearbox(l, kind: transmission, gears: gears))
            }
            if let seconds = zeroToHundredS, seconds > 0 {
                parts.append(AppStrings.garageAcceleration(l, value: UnitNumber.upToTenth(seconds, code: l.rawValue)))
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    enum CatalogError: Error { case unsupportedSchema }

    static func decode(_ data: Data) throws -> Document {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schema == 2 else { throw CatalogError.unsupportedSchema }
        return document
    }

    func resolve(modelID: String?, generationID: String?, variantID: String?) -> Variant? {
        guard let modelID, let generationID, let variantID else { return nil }
        if loaded == nil, let url = Bundle.main.url(forResource: "CarCatalog", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        {
            loaded = try? Self.decode(data)
        }
        return loaded?.makes.lazy.flatMap(\.models).first { $0.id == modelID }?
            .generations.first { $0.id == generationID }?.variants.first { $0.id == variantID }
    }
}
