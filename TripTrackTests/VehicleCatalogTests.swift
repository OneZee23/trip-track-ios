import XCTest
@testable import TripTrack

/// Справочник марок — данные, а не код, и ломается он тихо: опечатка в
/// названии кузова не мешает сборке, она просто оставляет модель без силуэта.
/// Эти тесты держат ровно те инварианты, которые нельзя увидеть глазами в
/// файле на 500 строк.
final class VehicleCatalogTests: XCTestCase {

    func testCatalogLoadsFromTheBundle() {
        // Если каталог не попал в ресурсы тестового таргета, всё остальное
        // здесь пройдёт на пустом массиве и ничего не проверит.
        XCTAssertFalse(VehicleCatalog.makes.isEmpty,
                       "каталог не найден в бандле — проверь project.yml")
        XCTAssertGreaterThan(VehicleCatalog.makes.count, 50)
    }

    func testEveryBodyIsAKnownSilhouette() {
        let known = Set(VehicleAvatar.styles)
        for make in VehicleCatalog.makes {
            for model in make.models {
                XCTAssertFalse(model.bodies.isEmpty,
                               "\(make.name) \(model.name): модель без кузова")
                for body in model.bodies {
                    XCTAssertTrue(known.contains(body),
                                  "\(make.name) \(model.name): силуэта «\(body)» не существует")
                }
            }
        }
    }

    func testNoDuplicateMakesOrModels() {
        var seenMakes = Set<String>()
        for make in VehicleCatalog.makes {
            XCTAssertTrue(seenMakes.insert(make.name).inserted,
                          "марка \(make.name) встречается дважды")
            var seenModels = Set<String>()
            for model in make.models {
                XCTAssertTrue(seenModels.insert(model.name).inserted,
                              "\(make.name): модель \(model.name) встречается дважды")
            }
        }
    }

    func testNamesAreTrimmedAndNonEmpty() {
        for make in VehicleCatalog.makes {
            XCTAssertEqual(make.name, make.name.trimmingCharacters(in: .whitespaces))
            XCTAssertFalse(make.name.isEmpty)
            for model in make.models {
                XCTAssertEqual(model.name, model.name.trimmingCharacters(in: .whitespaces))
                XCTAssertFalse(model.name.isEmpty)
            }
        }
    }

    // MARK: - Выборка по типу транспорта

    func testBicycleTypeNeverOffersCars() {
        // Прецедент из `VehicleAvatar.styles(forType:)`: предлагать пикап
        // тому, кто сказал «велосипед», — это список неправильных ответов.
        let makes = VehicleCatalog.makes(forType: "bicycle")

        XCTAssertFalse(makes.isEmpty)
        XCTAssertFalse(makes.contains { $0.name == "Toyota" })
        for make in makes {
            for model in make.models {
                XCTAssertTrue(model.bodies.contains("bicycle"),
                              "\(make.name) \(model.name) не велосипед")
            }
        }
    }

    func testAMakeSpanningTwoWorldsKeepsOnlyTheRightHalf() {
        // Honda делает и машины, и мотоциклы. Под «мото» её модели-машины
        // показывать нельзя, а саму марку — нужно.
        let moto = VehicleCatalog.makes(forType: "moto").first { $0.name == "Honda" }

        XCTAssertNotNil(moto, "Honda обязана остаться в списке мотоциклов")
        XCTAssertTrue(moto!.models.contains { $0.name == "CB400" })
        XCTAssertFalse(moto!.models.contains { $0.name == "Civic" },
                       "Civic не мотоцикл")
    }

    func testScooterAndMotorcycleDoNotMix() {
        let moped = VehicleCatalog.makes(forType: "moped")
        for make in moped {
            for model in make.models {
                XCTAssertTrue(model.bodies.contains("scooter"),
                              "\(make.name) \(model.name) не скутер")
            }
        }
        XCTAssertTrue(moped.contains { $0.name == "Vespa" })
    }

    // MARK: - Поиск

    func testSearchFindsAModelWithoutKnowingItsMake() {
        // «Solaris» человек помнит, «Hyundai» — не всегда.
        let hits = VehicleCatalog.search("solaris", type: "car")

        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.name, "Hyundai")
        XCTAssertEqual(hits.first?.models.map(\.name), ["Solaris"])
    }

    func testSearchByMakeKeepsAllItsModels() {
        let hits = VehicleCatalog.search("lada", type: "car")

        XCTAssertEqual(hits.count, 1)
        XCTAssertGreaterThan(hits.first!.models.count, 5,
                             "нашли марку — показываем весь её модельный ряд")
    }

    func testSearchIsFoldedWithoutALocaleOnPurpose() {
        // Этот тест первым делом упал на языковой свёртке и тем её и отменил:
        // под турецким «INFINITI» складывается в «ınfınıtı», а «Infiniti» —
        // в «ınfiniti», и марка переставала находиться у себя же в каталоге.
        // Марки — латинские имена собственные, а не копия на языке интерфейса.
        XCTAssertEqual(VehicleCatalog.search("INFINITI", type: "car").first?.name, "Infiniti")
        XCTAssertEqual(VehicleCatalog.search("infiniti", type: "car").first?.name, "Infiniti")
    }

    func testSearchIgnoresDiacriticsBecausePeopleTypeBothWays() {
        // В каталоге «Skoda» и «Citroen» без диакритики, а печатают часто с ней.
        XCTAssertEqual(VehicleCatalog.search("Škoda", type: "car").first?.name, "Skoda")
        XCTAssertEqual(VehicleCatalog.search("Citroën", type: "car").first?.name, "Citroen")
    }

    func testEmptyQueryReturnsTheWholeListForThatType() {
        XCTAssertEqual(VehicleCatalog.search("  ", type: "car").count,
                       VehicleCatalog.makes(forType: "car").count)
    }

    func testSearchMissReturnsNothingRatherThanEverything() {
        XCTAssertTrue(VehicleCatalog.search("щщщ", type: "car").isEmpty)
    }

    // MARK: - Алиасы: то, как марку НАБИРАЮТ

    /// Тот самый баг, ради которого алиасы и появились. Каталог смешивал
    /// скрипты: шесть марок кириллицей, Lada и UAZ латиницей, — и ни один из
    /// этих запросов не находил ничего. Поиск здесь единственный способ
    /// добраться до марки в списке из девяноста семи, то есть экран «марка и
    /// модель» просто не работал для рынка, ради которого каталог собран.
    func testTheQueriesThatUsedToFindNothing() {
        for (query, expected) in [("уаз", "UAZ"), ("лада", "Lada"), ("ваз", "Lada"),
                                  ("GAZ", "GAZ"), ("Moskvich", "Moskvich"),
                                  ("Иж", "IZh"), ("Урал", "Ural")] {
            let hits = VehicleCatalog.search(query, type: "car").map(\.name)
                + VehicleCatalog.search(query, type: "moto").map(\.name)
            XCTAssertTrue(hits.contains(expected),
                          "«\(query)» обязан находить \(expected), а нашёл \(hits)")
        }
    }

    func testCyrillicTypingFindsLatinMakes() {
        // Человек печатает «тойота», а в списке стоит «Toyota».
        for (query, expected) in [("тойота", "Toyota"), ("шкода", "Skoda"),
                                  ("мерседес", "Mercedes-Benz"), ("пежо", "Peugeot"),
                                  ("хендай", "Hyundai"), ("ямаха", "Yamaha")] {
            let hits = VehicleCatalog.search(query, type: "car").map(\.name)
                + VehicleCatalog.search(query, type: "moto").map(\.name)
            XCTAssertTrue(hits.contains(expected), "«\(query)» → \(expected), а не \(hits)")
        }
    }

    func testFolkNamesFindTheModel() {
        // «Буханка» — не шутка: УАЗ 3909 по заводскому индексу не ищет никто.
        let buhanka = VehicleCatalog.search("буханка", type: "car")
        XCTAssertEqual(buhanka.first?.name, "UAZ")
        XCTAssertEqual(buhanka.first?.models.map(\.name), ["3909"])

        let niva = VehicleCatalog.search("нива", type: "car")
        XCTAssertEqual(niva.first?.name, "Lada")
        XCTAssertTrue(niva.first!.models.count >= 2, "Нив в модельном ряду две")
    }

    /// Инвариант, который держит канон: имя в списке — латиница. Список читают
    /// на тринадцати языках, и «ГАЗ» в немецком интерфейсе нечитаем. Кириллица
    /// живёт в алиасах, и только там.
    func testCanonicalNamesAreLatinOnly() {
        // Блок Unicode, а не `CharacterSet(charactersIn: "А-Яа-я")`: там дефис
        // попал бы в набор буквально и уронил бы «Mercedes-Benz».
        func hasCyrillic(_ s: String) -> Bool {
            s.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
        }
        for make in VehicleCatalog.makes {
            XCTAssertFalse(hasCyrillic(make.name),
                           "марка «\(make.name)» записана кириллицей — канон латиница, кириллица в aliases")
            for model in make.models {
                XCTAssertFalse(hasCyrillic(model.name),
                               "\(make.name) «\(model.name)»: кириллица в имени модели")
            }
        }
    }

    /// Каждый алиас обязан находить свою же марку. Опечатка в алиасе иначе
    /// проходит молча: алиас есть, а не совпадает ни с чем — и это ровно тот
    /// класс тихой поломки, из-за которого поиск и не работал.
    func testEveryAliasFindsItsOwnMake() {
        let types = ["car", "moto", "moped", "bicycle"]
        for make in VehicleCatalog.makes {
            for alias in make.aliases ?? [] {
                let hits = types.flatMap { VehicleCatalog.search(alias, type: $0).map(\.name) }
                XCTAssertTrue(hits.contains(make.name),
                              "алиас «\(alias)» не находит \(make.name) — опечатка в таблице")
            }
            for model in make.models {
                for alias in model.aliases ?? [] {
                    let hits = types.flatMap { VehicleCatalog.search(alias, type: $0).map(\.name) }
                    XCTAssertTrue(hits.contains(make.name),
                                  "алиас «\(alias)» модели \(model.name) не находит \(make.name)")
                }
            }
        }
    }

    func testAliasesDoNotLeakIntoTheVisibleName() {
        // Алиас — только для поиска. В списке человек видит заводское имя.
        let toyota = VehicleCatalog.makes.first { $0.name == "Toyota" }
        XCTAssertEqual(toyota?.name, "Toyota")
        XCTAssertTrue(toyota?.aliases?.contains("Тойота") ?? false)
    }

    // MARK: - Силуэт, который подставляется

    func testChoosingAModelPreselectsItsSilhouette() {
        let polo = VehicleCatalog.makes.first { $0.name == "Volkswagen" }!
            .models.first { $0.name == "Polo" }!

        XCTAssertEqual(VehicleCatalog.defaultBody(for: polo, type: "car"), "car")
    }

    func testASilhouetteForeignToTheTypeIsNotHandedOut() {
        // Каталог предлагает, тип решает — то же правило, что у
        // `VehicleAvatar.resolveStyle(_:forType:)`.
        let pickup = VehicleCatalog.Model(name: "Hilux", bodies: ["pickup"], aliases: nil)

        XCTAssertEqual(VehicleCatalog.defaultBody(for: pickup, type: "moto"),
                       VehicleAvatar.defaultStyle(forType: "moto"))
    }
}
