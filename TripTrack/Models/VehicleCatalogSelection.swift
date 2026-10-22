import Foundation

struct VehicleCatalogSelection: Equatable {
    let make: String
    let model: String
    let body: String
    var year: Int?
    var catalogModelId: String?
    var catalogGenerationId: String?
    var catalogVariantId: String?

    init(make: String, model: String, body: String) {
        self.make = make
        self.model = model
        self.body = body
    }

    init(hit: CarCatalog.ModelHit, generation: CarCatalog.Generation, year: Int,
         variant: CarCatalog.Variant?, type: String) {
        make = hit.make.name
        model = hit.model.name
        body = VehicleCatalog.defaultBody(forCatalogBody: generation.bodies?.first, type: type)
        self.year = year
        catalogModelId = hit.model.id
        catalogGenerationId = generation.id
        catalogVariantId = variant?.id
    }

    mutating func clearCatalogIDs() {
        catalogModelId = ""
        catalogGenerationId = ""
        catalogVariantId = ""
    }
}
