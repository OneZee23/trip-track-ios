import CoreData
import XCTest

@testable import TripTrack

final class GarageDataTests: XCTestCase {
    func testDrive2NormalizesEveryAcceptedHost() {
        for host in ["drive2.ru", "www.drive2.ru", "m.drive2.ru", "drive2.com", "www.drive2.com"] {
            let link = Drive2Link("  http://\(host)/r/volkswagen/polo/123456/logbook/?utm=a#part \n")
            XCTAssertEqual(
                link?.url.absoluteString,
                "https://www.drive2.\(host.hasSuffix("com") ? "com" : "ru")/r/volkswagen/polo/123456/")
            XCTAssertEqual(link?.make, "volkswagen")
            XCTAssertEqual(link?.model, "polo")
        }
    }
    func testDrive2RejectsArbitraryAndSpoofedLinks() {
        for input in [
            "drive2.ru/r/vw/polo/123", "https://drive2.ru.evil.example/r/vw/polo/123/", "https://drive2.ru/users/test/",
            "https://drive2.ru/l/123/", "https://drive2.ru/r/vw/polo/abc/", "https://drive2.ru/r/vw/polo/123abc/",
            "https://user@drive2.ru/r/vw/polo/123/", "https://drive2.ru:443/r/vw/polo/123/",
            "https:drive2.ru/r/vw/polo/123/", "https://drive2.ru:/r/vw/polo/123/",
            "http://drive2.ru:80/r/vw/polo/123/",
            "ftp://drive2.ru/r/vw/polo/123/", "https://drive2.ru/r/vw/%70olo/123/",
        ] {
            XCTAssertNil(Drive2Link(input), input)
        }
    }
    func testTagsAreTrimmedLimitedDeduplicatedAndRetainedWhenExpired() {
        let tags = VehicleModTags.sanitized([
            "  CarPlay  ", "", "CarPlay", String(repeating: "я", count: 40), "Шумка", "fourth",
        ])
        XCTAssertEqual(tags, ["CarPlay", String(repeating: "я", count: 24), "Шумка"])
        XCTAssertEqual(VehicleModTags.effective(tags, isPlus: false), [])
        XCTAssertEqual(VehicleModTags.effective(tags, isPlus: true), tags)
        XCTAssertEqual(VehicleModTags.decodeJSON(VehicleModTags.encodeJSON(tags)), tags)
    }
    func testFinishAvailabilityAndExpiredFallback() {
        XCTAssertEqual(VehicleFinish.availableFinishes, [.gloss, .matte])
        for finish in VehicleFinish.allCases {
            let stored = finish.rawValue
            XCTAssertEqual(VehicleFinish.effective(stored, isPlus: false), .gloss)
            XCTAssertEqual(VehicleFinish.effective(stored, isPlus: true), finish)
            XCTAssertEqual(stored, finish.rawValue)
        }
        XCTAssertEqual(VehicleFinish.effective("future", isPlus: true), .gloss)
    }
    func testEveryPlatformFallsBackWithoutErasingSelection() {
        for style in VehicleCardStyle.allCases {
            XCTAssertEqual(style.effective(isPlus: false), .none)
            XCTAssertEqual(style.effective(isPlus: true), style)
        }
    }
    func testModsRoundTripAndOrderByDayWithStableTies() {
        let a = VehicleMod(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, title: "CarPlay", date: "2025-08-18",
            odometerKm: 91200, photoIds: [UUID()])
        let b = VehicleMod(title: "Шумка", date: "2026-03-12", odometerKm: nil)
        let c = VehicleMod(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, title: "Шины", date: a.date,
            odometerKm: 93400)
        XCTAssertEqual(VehicleMod.decodeJSON(VehicleMod.encodeJSON([a, b, c])), [a, b, c])
        XCTAssertEqual(VehicleMod.ordered([c, b, a]).map(\.id), [b.id, a.id, c.id])
        XCTAssertEqual(VehicleMod.decodeJSON("broken"), [])
    }
    func testDateBoundsNeverInvertForFutureOrPreEpochSelection() {
        let now = Date(timeIntervalSince1970: 10000)
        for selection in [Date(timeIntervalSince1970: -20000), now, now.addingTimeInterval(10000)] {
            let range = VehicleMod.dateBounds(selected: selection, now: now)
            XCTAssertLessThanOrEqual(range.lowerBound, range.upperBound)
            XCTAssertEqual(range.upperBound, now)
        }
    }
    func testYearlyDistanceUsesConfirmedTripsOfThisCarOnly() {
        let id = UUID()
        let other = UUID()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        func trip(_ year: Int, _ km: Double, car: UUID? = nil, transfer: Bool = false, draft: Bool = false) -> Trip {
            var t = Trip(
                id: UUID(), startDate: cal.date(from: DateComponents(year: year, month: 6, day: 1))!,
                distance: km * 1000)
            t.vehicleId = car ?? id
            t.isTransfer = transfer
            t.confirmation = draft ? .draft : .confirmed
            return t
        }
        XCTAssertEqual(
            VehicleYearDistance.aggregate(
                [
                    trip(2025, 2), trip(2026, 4), trip(2025, 3), trip(2026, 100, car: other),
                    trip(2026, 200, transfer: true), trip(2026, 300, draft: true),
                ], vehicleID: id, calendar: cal), [.init(year: 2025, km: 5), .init(year: 2026, km: 4)])
    }
    private func payload(_ id: UUID = UUID()) -> VehicleSyncPayload {
        .init(
            id: id, name: "Car", avatarEmoji: "🚗", odometerKm: 0, level: 1, stickersJson: nil, cityConsumption: 10,
            highwayConsumption: 6, fuelPrice: 1, conflictVersion: 1, lastModifiedAt: Date())
    }
    func testGarageWireRoundTripAndMissingKeys() throws {
        var p = payload()
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let absent = try JSONSerialization.jsonObject(with: encoder.encode(p)) as! [String: Any]
        for key in [
            "drive2Url", "modTags", "paintFinish", "mods", "catalogModelId", "catalogGenerationId", "catalogVariantId",
        ] { XCTAssertNil(absent[key]) }
        let old = try decoder.decode(VehicleSyncPayload.self, from: encoder.encode(p))
        XCTAssertNil(old.drive2Url)
        XCTAssertNil(old.mods)
        p.drive2Url = "https://www.drive2.ru/r/volkswagen/polo/123/"
        p.modTags = ["CarPlay"]
        p.paintFinish = "future-finish"
        p.mods = [VehicleMod(title: "Test", date: "2026-03-12")]
        p.catalogModelId = "volkswagen-polo"
        p.catalogGenerationId = "volkswagen-polo-sedan-2015"
        p.catalogVariantId = "volkswagen-polo-sedan-2015-16-110-at6"
        let back = try decoder.decode(VehicleSyncPayload.self, from: encoder.encode(p))
        XCTAssertEqual(back.drive2Url, p.drive2Url)
        XCTAssertEqual(back.modTags, p.modTags)
        XCTAssertEqual(back.paintFinish, p.paintFinish)
        XCTAssertEqual(back.mods, p.mods)
        XCTAssertEqual(back.catalogModelId, p.catalogModelId)
        XCTAssertEqual(back.catalogGenerationId, p.catalogGenerationId)
        XCTAssertEqual(back.catalogVariantId, p.catalogVariantId)
    }
    func testRemoteGarageKeepsPendingEditsAndUnderstandsSilenceAndClear() throws {
        for pending in [false, true] {
            let pc = PersistenceController(inMemory: true)
            let repo = CoreDataTripRepository(persistenceController: pc)
            let id = UUID()
            let e = VehicleEntity(context: pc.container.viewContext)
            e.id = id
            e.name = "Car"
            e.avatarEmoji = "🚗"
            e.drive2URL = "https://www.drive2.ru/r/vw/polo/123/"
            e.paintFinish = "matte"
            e.modTagsJSON = "[\"CarPlay\"]"
            e.modsJSON = "[]"
            e.catalogModelId = "old"
            e.syncStatus = pending ? SyncStatus.pendingUpload.rawValue : SyncStatus.synced.rawValue
            e.lastModifiedAt = Date()
            try pc.container.viewContext.save()
            repo.applyRemoteVehicle(payload(id))
            XCTAssertEqual(e.paintFinish, "matte")
            XCTAssertEqual(e.catalogModelId, "old")
            var p = payload(id)
            p.drive2Url = ""
            p.modTags = []
            p.paintFinish = "gloss"
            p.mods = [VehicleMod(title: "Fresh", date: "2026-01-01")]
            p.catalogModelId = "new"
            repo.applyRemoteVehicle(p)
            XCTAssertEqual(e.drive2URL, pending ? "https://www.drive2.ru/r/vw/polo/123/" : "")
            XCTAssertEqual(e.paintFinish, pending ? "matte" : "gloss")
            XCTAssertEqual(e.catalogModelId, pending ? "old" : "new")
            XCTAssertEqual(VehicleModTags.decodeJSON(e.modTagsJSON), pending ? ["CarPlay"] : [])
            XCTAssertEqual(VehicleMod.decodeJSON(e.modsJSON).count, pending ? 0 : 1)
            XCTAssertEqual(e.syncStatus, pending ? SyncStatus.pendingUpload.rawValue : SyncStatus.synced.rawValue)
        }
    }
    func testUploadDistinguishesUnknownColumnsFromExplicitEmptyValues() throws {
        let pc = PersistenceController(inMemory: true)
        let entity = VehicleEntity(context: pc.container.viewContext)
        var p = payload()
        p.applyGarageFields(from: entity)
        XCTAssertNil(p.drive2Url)
        XCTAssertNil(p.modTags)
        XCTAssertNil(p.paintFinish)
        XCTAssertNil(p.mods)
        XCTAssertNil(p.catalogModelId)
        entity.drive2URL = ""
        entity.modTagsJSON = "[]"
        entity.modsJSON = "[]"
        entity.catalogModelId = ""
        entity.paintFinish = "gloss"
        p.applyGarageFields(from: entity)
        XCTAssertEqual(p.drive2Url, "")
        XCTAssertEqual(p.modTags, [])
        XCTAssertEqual(p.mods, [])
        XCTAssertEqual(p.catalogModelId, "")
        XCTAssertEqual(p.paintFinish, "gloss")
    }

    func testPublicVehicleToleratesUnknownNewFields() throws {
        let json = """
            {"id":"\(UUID())","name":"Car","avatarEmoji":"🚗","level":1,"odometerKm":0,"paintFinish":"future","mods":false,"modTags":42,"catalogVariantId":false}
            """
        let p = try JSONDecoder().decode(PublicVehicle.self, from: Data(json.utf8))
        XCTAssertEqual(p.paintFinish, "future")
        XCTAssertNil(p.mods)
        XCTAssertNil(p.modTags)
        XCTAssertNil(p.catalogVariantId)
    }
    func testCatalogResolvesExactVariantAndNeverGuesses() async throws {
        let variant = await CarCatalog.shared.resolve(
            modelID: "volkswagen-polo", generationID: "volkswagen-polo-sedan-2015",
            variantID: "volkswagen-polo-sedan-2015-16-110-at6")
        XCTAssertEqual(variant?.powerHp, 110)
        XCTAssertEqual(variant?.displacementCc, 1598)
        let missing = await CarCatalog.shared.resolve(
            modelID: "haval-jolion", generationID: "volkswagen-polo-sedan-2015", variantID: variant?.id)
        XCTAssertNil(missing)
        XCTAssertThrowsError(try CarCatalog.decode(Data("{\"schema\":3,\"makes\":[]}".utf8)))
        for l in LanguageManager.Language.allCases {
            let line = try XCTUnwrap(variant?.specLine(l))
            XCTAssertTrue(line.contains("11.7"), line)
            XCTAssertFalse(line.contains("11,7"))
            XCTAssertFalse(AppStrings.garageDrive2Title(l).isEmpty)
        }
    }

    /// The bundled catalog is the real one (50 models, schema 2), not a
    /// placeholder, and the ids the debug seeds use resolve in it. A DHT hybrid
    /// ships `transmission: null` — it must still decode and simply drop the
    /// gearbox from the spec line.
    func testBundledCatalogIsTheFullOneAndSeedIdsResolve() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "CarCatalog", withExtension: "json"))
        let document = try CarCatalog.decode(Data(contentsOf: url))
        let models = document.makes.flatMap(\.models)
        XCTAssertEqual(models.count, 50)
        let ids = models.flatMap { m in m.generations.flatMap { g in [g.id] + g.variants.map(\.id) } } + models.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Catalog ids are stored in people's cars and must be unique")
        let jolion = await CarCatalog.shared.resolve(
            modelID: "haval-jolion", generationID: "haval-jolion-2021",
            variantID: "haval-jolion-2021-15t-143-dct7")
        XCTAssertEqual(jolion?.powerHp, 143)
        let niva = models.flatMap { $0.generations.flatMap(\.variants) }.first { $0.powerHp == 79.6 }
        XCTAssertEqual(niva?.specLine(.ru)?.contains("79.6"), true, "Fractional horsepower is shown as published")
        let dht = models.flatMap { $0.generations.flatMap(\.variants) }.first { $0.transmission == nil && $0.id.hasSuffix("-dht") }
        if let dht, let line = dht.specLine(.ru) {
            XCTAssertFalse(line.contains("АКПП") || line.contains("вариатор"), line)
        }
    }
}
