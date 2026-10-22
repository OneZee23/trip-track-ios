import XCTest
@testable import TripTrack

final class CarCatalogSearchTests: XCTestCase {
    private func catalog() throws -> CarCatalog {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "CarCatalog", withExtension: "json"))
        return CarCatalog(document: try CarCatalog.decode(Data(contentsOf: url)))
    }

    func testPoloIsFirstAndAliasesCombineAcrossMakeAndModel() async throws {
        let catalog = try catalog()
        for query in ["polo", "  PoLo  ", "фольксваген поло седан", "ФОЛЬКСВАГЕН   ПОЛО"] {
            let hits = await catalog.search(query)
            XCTAssertEqual(hits.first?.model.id, "volkswagen-polo", query)
            XCTAssertEqual(hits.first?.make.name, "Volkswagen")
        }
        let nonsense = await catalog.search("nonexistent-model-xyz")
        XCTAssertTrue(nonsense.isEmpty)
    }

    func testYearFiltersModelsAndPrioritizesGeneration() async throws {
        let catalog = try catalog()
        let hits = await catalog.search("поло 2018")
        let hit = try XCTUnwrap(hits.first)
        XCTAssertEqual(hit.model.id, "volkswagen-polo")
        XCTAssertEqual(hit.matchedYear, 2018)
        XCTAssertEqual(hit.yearStart, hit.model.generations.compactMap(\.yearStart).min())
        XCTAssertEqual(hit.yearEnd, hit.model.generations.map { $0.yearEnd ?? Calendar.current.component(.year, from: Date()) }.max())
        let generations = await catalog.generations(of: hit.model.id, year: hit.matchedYear)
        XCTAssertEqual(generations.first?.id, "volkswagen-polo-sedan-2015")
        XCTAssertEqual(generations.count, hit.model.generations.count)
        let tooEarly = await catalog.search("polo 1990")
        XCTAssertTrue(tooEarly.isEmpty)
    }

    func testYoAndWhitespaceAndOpenEndedModelSpan() async throws {
        let document = try CarCatalog.decode(Data("""
            {"schema":2,"makes":[{"id":"test","name":"Test","nameRu":"Тёст","aliases":[],
            "models":[{"id":"test-model","name":"Model","aliases":["Модель"],
            "generations":[{"id":"test-generation","name":"First","yearStart":2000,"variants":[]}]}]}]}
            """.utf8))
        let catalog = CarCatalog(document: document)
        let current = Calendar.current.component(.year, from: Date())
        let hits = await catalog.search("  ТЕСТ  модель  " + String(current))
        XCTAssertEqual(hits.first?.model.id, "test-model")
        XCTAssertEqual(hits.first?.matchedYear, current)
        XCTAssertEqual(hits.first?.yearEnd, current)
        let yo = await catalog.search("тёст")
        XCTAssertEqual(yo.count, 1)
    }

    func testVariantOwnYearsAreRespectedAndUndatedVariantsRemain() async throws {
        let catalog = try catalog()
        let generation = "volkswagen-polo-sedan-2015"
        let in2018 = await catalog.variants(of: generation, year: 2018)
        XCTAssertTrue(in2018.contains { $0.id == generation + "-16-110-at6" })
        XCTAssertFalse(in2018.contains { $0.id == generation + "-16-105-at6" })
        let in2015 = await catalog.variants(of: generation, year: 2015)
        XCTAssertTrue(in2015.contains { $0.id == generation + "-16-105-at6" })
        XCTAssertFalse(in2015.contains { $0.id == generation + "-14t-125-dct7" })
        let undated = await catalog.variants(of: "volkswagen-polo-liftback-2020", year: 2021)
        let all = await catalog.variants(of: "volkswagen-polo-liftback-2020")
        XCTAssertEqual(undated, all)
    }

    func testSelectionRoundTripsIDsAndExplicitlyClearsThem() async throws {
        let catalog = try catalog()
        let hits = await catalog.search("polo 2018")
        let hit = try XCTUnwrap(hits.first)
        let generations = await catalog.generations(of: hit.model.id, year: 2018)
        let generation = try XCTUnwrap(generations.first)
        let variants = await catalog.variants(of: generation.id, year: 2018)
        let variant = try XCTUnwrap(variants.first { $0.id.hasSuffix("-16-110-at6") })
        var selection = VehicleCatalogSelection(hit: hit, generation: generation, year: 2018, variant: variant, type: "car")
        XCTAssertEqual(selection.make, "Volkswagen")
        XCTAssertEqual(selection.model, "Polo")
        XCTAssertEqual(selection.year, 2018)
        XCTAssertEqual(selection.body, "car")
        let resolved = await catalog.resolve(modelID: selection.catalogModelId,
            generationID: selection.catalogGenerationId, variantID: selection.catalogVariantId)
        XCTAssertEqual(resolved, variant)
        let unknown = VehicleCatalogSelection(hit: hit, generation: generation, year: 2018, variant: nil, type: "car")
        XCTAssertEqual(unknown.catalogModelId, hit.model.id)
        XCTAssertEqual(unknown.catalogGenerationId, generation.id)
        XCTAssertNil(unknown.catalogVariantId)
        selection.clearCatalogIDs()
        XCTAssertEqual(selection.catalogModelId, "")
        XCTAssertEqual(selection.catalogGenerationId, "")
        XCTAssertEqual(selection.catalogVariantId, "")
        for (body, style) in [("sedan", "car"), ("liftback", "car"), ("suv", "crossover"), ("wagon", "hatchback")] {
            XCTAssertEqual(VehicleCatalog.defaultBody(forCatalogBody: body, type: "car"), style)
        }
        XCTAssertEqual(VehicleCatalog.defaultBody(forCatalogBody: "sedan", type: "bicycle"), "bicycle")
    }
}
