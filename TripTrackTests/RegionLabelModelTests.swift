import XCTest
import CoreLocation
@testable import TripTrack

/// `RegionLabelModel`: какое имя получает подпись на каждом языке, кто
/// получает подпись вообще (только посещённые регионы), и как строка
/// километров зависит от единицы — все чистыми функциями.
final class RegionLabelModelTests: XCTestCase {

    private let kuban = RegionAtlas.Region(
        id: "RU-KDA", countryCode: "RU", nameRu: "Краснодарский край", nameEn: "Krasnodar Krai",
        center: CLLocationCoordinate2D(latitude: 45.0, longitude: 39.0),
        bounds: GeoBounds(minLat: 44.0, maxLat: 46.5, minLon: 36.5, maxLon: 41.0),
        rings: []
    )

    private func layer(km: Double) -> RevealedLayer {
        var layer = RevealedLayer.empty
        layer.regionKm = ["RU-KDA": km]
        return layer
    }

    // MARK: - Регион: язык ru/en/fallback

    func testRegionNameRussian() {
        let labels = RegionLabelModel.regionLabels(
            regions: [kuban], revealed: layer(km: 100), visitedRegionIds: ["RU-KDA"],
            unit: .km, language: .ru
        )
        XCTAssertEqual(labels.first?.name, "КРАСНОДАРСКИЙ КРАЙ")
    }

    func testRegionNameEnglish() {
        let labels = RegionLabelModel.regionLabels(
            regions: [kuban], revealed: layer(km: 100), visitedRegionIds: ["RU-KDA"],
            unit: .km, language: .en
        )
        XCTAssertEqual(labels.first?.name, "KRASNODAR KRAI")
    }

    func testRegionNameFallsBackToEnglishForOtherLanguages() {
        // Третий язык (не ru/en) не хранится отдельно — правило «ru/en по
        // языку, для остальных en».
        let labels = RegionLabelModel.regionLabels(
            regions: [kuban], revealed: layer(km: 100), visitedRegionIds: ["RU-KDA"],
            unit: .km, language: .de
        )
        XCTAssertEqual(labels.first?.name, "KRASNODAR KRAI")
    }

    // MARK: - Только посещённые регионы

    func testUnvisitedRegionGetsNoLabel() {
        let labels = RegionLabelModel.regionLabels(
            regions: [kuban], revealed: layer(km: 0), visitedRegionIds: [], unit: .km, language: .ru
        )
        XCTAssertTrue(labels.isEmpty)
    }

    func testVisitedRegionUsesBundleCentroid() {
        // Центроид — из бандла (`Region.center`), не из открытой части слоя.
        let labels = RegionLabelModel.regionLabels(
            regions: [kuban], revealed: layer(km: 100), visitedRegionIds: ["RU-KDA"],
            unit: .km, language: .ru
        )
        XCTAssertEqual(labels.first?.coordinate.latitude, kuban.center.latitude)
        XCTAssertEqual(labels.first?.coordinate.longitude, kuban.center.longitude)
    }

    // MARK: - Строка километров через Measure, с явной единицей

    func testKmLineUsesMeasureInKilometres() {
        let labels = RegionLabelModel.regionLabels(
            regions: [kuban], revealed: layer(km: 143.2), visitedRegionIds: ["RU-KDA"],
            unit: .km, language: .ru
        )
        XCTAssertEqual(labels.first?.kmLine, Measure.distance(km: 143.2, unit: .km, lang: .ru))
    }

    func testKmLineUsesMeasureInMiles() {
        let labels = RegionLabelModel.regionLabels(
            regions: [kuban], revealed: layer(km: 143.2), visitedRegionIds: ["RU-KDA"],
            unit: .miles, language: .en
        )
        XCTAssertEqual(labels.first?.kmLine, Measure.distance(km: 143.2, unit: .miles, lang: .en))
        XCTAssertNotEqual(labels.first?.kmLine, Measure.distance(km: 143.2, unit: .km, lang: .en))
    }
}
