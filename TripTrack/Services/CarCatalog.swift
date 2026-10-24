import Foundation

actor CarCatalog {
    static let shared = CarCatalog()
    private var loaded: Document?

    init(document: Document? = nil) { loaded = document }

    struct Document: Decodable, Sendable {
        let schema: Int
        let makes: [Make]
    }

    struct Make: Decodable, Sendable {
        let id: String
        let name: String
        let nameRu: String?
        let aliases: [String]?
        let models: [Model]
    }

    struct Model: Decodable, Sendable {
        let id: String
        let name: String
        let aliases: [String]?
        let generations: [Generation]
    }

    struct Generation: Decodable, Sendable {
        let id: String
        let name: String
        let yearStart: Int?
        let yearEnd: Int?
        let bodies: [String]?
        let variants: [Variant]
    }

    struct Variant: Decodable, Equatable, Sendable {
        let id: String
        let label: String?
        let fuel: String?
        let displacementCc: Double?
        /// Double, not Int: Russian makers publish fractional horsepower
        /// (Niva 79.6, UAZ 134.6 л.с.), and one such value decoded as Int
        /// failed the WHOLE catalog. Shown up to a tenth, as published.
        let powerHp: Double?
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
            if let hp = powerHp, hp > 0 { engine.append(AppStrings.garagePower(l, value: UnitNumber.upToTenth(hp, code: l.rawValue))) }
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

    struct ModelHit: Sendable {
        let make: Make
        let model: Model
        let yearStart: Int?
        let yearEnd: Int?
        let matchedYear: Int?
    }

    private func loadIfNeeded() {
        guard loaded == nil,
              let url = Bundle.main.url(forResource: "CarCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        loaded = try? Self.decode(data)
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "ё", with: "е")
    }

    private static func covers(_ year: Int, start: Int?, end: Int?) -> Bool {
        year >= (start ?? Int.min) && year <= (end ?? Int.max)
    }

    func search(_ query: String) -> [ModelHit] {
        loadIfNeeded()
        let tokens = Self.fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let currentYear = Calendar.current.component(.year, from: Date())
        let year = tokens.first { $0.count == 4 && (1990...currentYear).contains(Int($0) ?? 0) }.flatMap(Int.init)
        let words = tokens.filter { $0 != year.map(String.init) }
        return (loaded?.makes ?? []).flatMap { make in
            make.models.compactMap { model -> ModelHit? in
                let names = [make.name, make.nameRu ?? "", model.name] + (make.aliases ?? []) + (model.aliases ?? [])
                let haystack = Self.fold(names.joined(separator: " "))
                guard words.allSatisfy({ haystack.contains($0) }) else { return nil }
                if let year, !model.generations.contains(where: {
                    Self.covers(year, start: $0.yearStart, end: $0.yearEnd)
                }) { return nil }
                return ModelHit(make: make, model: model,
                                yearStart: model.generations.compactMap(\.yearStart).min(),
                                yearEnd: model.generations.map { $0.yearEnd ?? currentYear }.max(), matchedYear: year)
            }
        }.sorted { lhs, rhs in
            let leftExact = words.contains(Self.fold(lhs.model.name))
            let rightExact = words.contains(Self.fold(rhs.model.name))
            if leftExact != rightExact { return leftExact }
            return lhs.make.name + " " + lhs.model.name < rhs.make.name + " " + rhs.model.name
        }
    }

    func generations(of modelID: String, year: Int? = nil) -> [Generation] {
        loadIfNeeded()
        let all = loaded?.makes.flatMap(\.models).first { $0.id == modelID }?.generations ?? []
        guard let year else { return all }
        let matches: (Generation) -> Bool = { Self.covers(year, start: $0.yearStart, end: $0.yearEnd) }
        return all.filter(matches) + all.filter { !matches($0) }
    }

    func variants(of generationID: String, year: Int? = nil) -> [Variant] {
        loadIfNeeded()
        let all = loaded?.makes.flatMap(\.models).flatMap(\.generations)
            .first { $0.id == generationID }?.variants ?? []
        guard let year else { return all }
        return all.filter { Self.covers(year, start: $0.yearStart, end: $0.yearEnd) }
    }

    func resolve(modelID: String?, generationID: String?, variantID: String?) -> Variant? {
        guard let modelID, let generationID, let variantID else { return nil }
        loadIfNeeded()
        return loaded?.makes.lazy.flatMap(\.models).first { $0.id == modelID }?
            .generations.first { $0.id == generationID }?.variants.first { $0.id == variantID }
    }
}
