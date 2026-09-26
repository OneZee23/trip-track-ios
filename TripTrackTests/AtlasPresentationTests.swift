import XCTest
import CoreLocation
import UIKit
@testable import TripTrack

final class AtlasPresentationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testYearUsesLocalCalendarBoundaries() {
        let now = date(2026, 9, 25)
        XCTAssertTrue(AtlasPeriod.thisYear.contains(date(2026, 1, 1, 0), now: now, calendar: calendar))
        XCTAssertFalse(AtlasPeriod.thisYear.contains(date(2025, 12, 31, 23), now: now, calendar: calendar))
        XCTAssertFalse(AtlasPeriod.thisYear.contains(date(2027, 1, 1, 0), now: now, calendar: calendar))
    }

    func testLastThirtyDaysIncludesTodayAcrossDaylightSaving() {
        let now = date(2026, 4, 5)
        let period = AtlasPeriod.last30Days
        XCTAssertTrue(period.contains(date(2026, 3, 7, 0), now: now, calendar: calendar))
        XCTAssertFalse(period.contains(date(2026, 3, 6, 23), now: now, calendar: calendar))
        XCTAssertTrue(period.contains(date(2026, 4, 5, 23), now: now, calendar: calendar))
        XCTAssertFalse(period.contains(date(2026, 4, 6, 0), now: now, calendar: calendar))
    }

    func testCustomPeriodIncludesEntireLastDayAndNormalizesReversedDates() {
        let start = date(2026, 9, 3), end = date(2026, 9, 5)
        for period in [AtlasPeriod.custom(start: start, end: end), .custom(start: end, end: start)] {
            XCTAssertTrue(period.contains(date(2026, 9, 3, 0), calendar: calendar))
            XCTAssertTrue(period.contains(date(2026, 9, 5, 23), calendar: calendar))
            XCTAssertFalse(period.contains(date(2026, 9, 6, 0), calendar: calendar))
        }
    }

    /// Границы календаря «своего периода». `ClosedRange` из двух дат роняет
    /// процесс, если нижняя больше верхней, — собирать его можно только так,
    /// чтобы перевернуть было нельзя (та же ловушка, что у
    /// `JourneyEditSheet.startBounds`).
    func testPeriodBoundsNeverInvertOnReversedOrFutureDates() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let future = now.addingTimeInterval(86_400 * 30)
        let ancient = now.addingTimeInterval(-86_400 * 365 * 50)

        for (start, end) in [(future, ancient), (ancient, future), (now, now), (future, future)] {
            let startRange = AtlasPeriodBounds.start(start: start, end: end, now: now)
            let endRange = AtlasPeriodBounds.end(start: start, end: end, now: now)
            XCTAssertLessThanOrEqual(startRange.lowerBound, startRange.upperBound)
            XCTAssertLessThanOrEqual(endRange.lowerBound, endRange.upperBound)
            XCTAssertLessThanOrEqual(startRange.upperBound, now, "начало нельзя выбрать в будущем")
            XCTAssertEqual(endRange.upperBound, now, "конец окна — сегодня, поездок из будущего нет")
        }
    }

    /// Окно из базы или с другого телефона приводится к допустимому.
    func testClampNormalizesOrderAndCutsTheFuture() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let later = now.addingTimeInterval(86_400 * 5)
        let earlier = now.addingTimeInterval(-86_400 * 5)

        let window = AtlasPeriodBounds.clamp(start: later, end: earlier, now: now)
        XCTAssertEqual(window.start, earlier, "перевёрнутая пара становится по порядку")
        XCTAssertEqual(window.end, now, "будущий конец срезается сегодняшним днём")
        XCTAssertLessThanOrEqual(window.start, window.end)
    }

    func testAllTimeDoesNotRestrictDates() {
        XCTAssertNil(AtlasPeriod.allTime.interval())
        XCTAssertTrue(AtlasPeriod.allTime.contains(.distantPast))
        XCTAssertTrue(AtlasPeriod.allTime.contains(.distantFuture))
    }

    private func trip(start: Date) -> Trip {
        let route = (0...40).map { step in
            CLLocationCoordinate2D(latitude: 45 + Double(step) * 0.0005, longitude: 39)
        }
        var trip = Trip(startDate: start)
        trip.previewPolyline = Trip.encodePolyline(route)
        return trip
    }

    func testPeriodLayerDeduplicatesRepeatedRoadsWithoutChangingInputs() {
        let first = trip(start: date(2026, 9, 1))
        let second = trip(start: date(2026, 9, 2))
        let once = AtlasPreviewLayer.build(trips: [first], atlas: nil)
        let repeated = AtlasPreviewLayer.build(trips: [second, first], atlas: nil)
        XCTAssertGreaterThan(once.openedKm, 1)
        XCTAssertEqual(repeated.openedKm, once.openedKm, accuracy: 0.0001)
        XCTAssertEqual(repeated.cellCount, once.cellCount)
        XCTAssertTrue(first.trackPoints.isEmpty)
        XCTAssertTrue(second.trackPoints.isEmpty)
    }

    func testMissingPreviewNeverFallsBackToRawTrackPoints() {
        var trip = Trip(startDate: date(2026, 9, 1))
        trip.trackPoints = [
            TrackPoint(latitude: 45, longitude: 39, altitude: 0, speed: 10, timestamp: trip.startDate),
            TrackPoint(latitude: 45.02, longitude: 39, altitude: 0, speed: 10,
                       timestamp: trip.startDate.addingTimeInterval(60))
        ]
        XCTAssertTrue(AtlasPreviewLayer.build(trips: [trip], atlas: nil).isEmpty)
    }

    func testFilteringByPeriodRemovesRoadsOutsideTheSelectedDates() {
        let old = trip(start: date(2025, 9, 1))
        let current = trip(start: date(2026, 9, 1))
        let trips = [old, current].filter {
            AtlasPeriod.thisYear.contains($0.startDate, now: date(2026, 9, 25), calendar: calendar)
        }
        XCTAssertEqual(trips.map(\.id), [current.id])
        XCTAssertFalse(AtlasPreviewLayer.build(trips: trips, atlas: nil).isEmpty)
        XCTAssertTrue(AtlasPreviewLayer.build(trips: [], atlas: nil).isEmpty)
    }

    func testAppearanceSurvivesReloadWithoutAffectingOtherDefaults() throws {
        let name = "AtlasPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(AtlasMapAppearance.load(defaults: defaults), AtlasMapAppearance())
        var appearance = AtlasMapAppearance()
        appearance.style = .night
        appearance.showsPhotos = false
        appearance.save(defaults: defaults)
        XCTAssertEqual(AtlasMapAppearance.load(defaults: defaults), appearance)
    }

    @MainActor
    func testExplicitMapStyleIsIndependentOfTheInterfaceTheme() {
        let previousPalette = FogVeilPainter.palette
        let previousMetalOverride = FogMetalAvailability.isEnabledOverride
        FogMetalAvailability.isEnabledOverride = false
        defer {
            FogVeilPainter.palette = previousPalette
            FogMetalAvailability.isEnabledOverride = previousMetalOverride
            CloudTexture.shared.forget()
        }
        let host = MapHostController()
        for theme in [UIUserInterfaceStyle.light, .dark] {
            host.overrideUserInterfaceStyle = theme
            host.setAppearance(AtlasMapAppearance(style: .fog))
            XCTAssertFalse(FogVeilPainter.palette.isDark, "Fog must stay light in either interface theme")
            host.setAppearance(AtlasMapAppearance(style: .night))
            XCTAssertTrue(FogVeilPainter.palette.isDark, "Night must stay dark in either interface theme")
        }
    }

    func testOverviewKeepsSameNamedCitiesInDifferentRegionsDistinct() {
        let a = region("RU-A", city: city("Мирный", latitude: 45))
        let b = region("RU-B", city: city("Мирный", latitude: 46))
        let index = AtlasOverviewIndex(exploration: MapExploration(regions: [a, b]))
        XCTAssertEqual(index.cityCount, 2)
        XCTAssertEqual(Set(index.cities(language: .ru).map(\.id)).count, 2)
        XCTAssertEqual(index.countries.count, 1)
        XCTAssertEqual(index.countries.first?.regions.count, 2)
        XCTAssertEqual(index.search("  мИрНыЙ  ", language: .ru).cities.count, 2)
    }

    func testGlobalSearchIncludesUnopenedPlacesWithoutInflatingExplorationStats() {
        let visitedCity = city("Краснодар", latitude: 45)
        let opened = region("RU-KDA", city: visitedCity)
        let unopenedRegion = RegionAtlas.Region(
            id: "RU-NVS", countryCode: "RU", nameRu: "Новосибирская область", nameEn: "Novosibirsk Oblast",
            center: .init(latitude: 55, longitude: 83),
            bounds: GeoBounds(minLat: 54, maxLat: 56, minLon: 82, maxLon: 84), rings: [])
        let unopenedCity = RegionAtlas.City(name: "Новосибирск", nameEn: "Novosibirsk", regionId: "RU-NVS",
                                           coordinate: .init(latitude: 55, longitude: 83), population: 1_000_000)
        let index = AtlasOverviewIndex(exploration: MapExploration(regions: [opened]),
                                       catalogRegions: [unopenedRegion], catalogCities: [unopenedCity])
        let results = index.search("нОвОсИ", language: .ru)
        XCTAssertEqual(results.regions.map(\.id), ["RU-NVS"])
        XCTAssertEqual(results.cities.count, 1)
        XCTAssertFalse(results.regions[0].isVisited)
        XCTAssertFalse(results.cities[0].wasVisited)
        XCTAssertEqual(index.cityCount, 1)
        XCTAssertEqual(index.countries.first?.regions.map(\.id), ["RU-KDA"])
    }

    func testSearchDoesNotCallAPlaceUnopenedWhenItWasVisitedOutsideThePeriod() {
        let oldCity = city("Краснодар", latitude: 45)
        let historical = MapExploration(regions: [region("RU-KDA", city: oldCity)])
        let catalogCity = RegionAtlas.City(name: oldCity.name, nameEn: oldCity.nameEn, regionId: "RU-KDA",
                                           coordinate: oldCity.coordinate, population: 1_000_000)
        let index = AtlasOverviewIndex(exploration: MapExploration(), catalogCities: [catalogCity],
                                       historical: historical)
        let result = index.search("Краснодар", language: .ru).cities.first
        XCTAssertFalse(result?.isVisited ?? true)
        XCTAssertTrue(result?.wasVisited ?? false)
        XCTAssertEqual(index.cityCount, 0)
    }

    private func city(_ name: String, latitude: Double) -> MapCityStat {
        MapCityStat(name: name, nameEn: name, coordinate: .init(latitude: latitude, longitude: 39), coverage: 0.5)
    }

    private func region(_ id: String, city: MapCityStat) -> MapRegionStat {
        MapRegionStat(id: id, countryCode: "RU", nameRu: id, nameEn: id, km: 1,
                      tripIds: [], cities: [city], totalCities: 3, openedTiles: 1,
                      firstVisited: nil, openedKm: 1, center: city.coordinate,
                      bounds: GeoBounds(minLat: 44, maxLat: 47, minLon: 38, maxLon: 40))
    }
}
