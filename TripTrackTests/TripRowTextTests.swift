import XCTest
@testable import TripTrack

/// Строка поездки в гараже.
///
/// Первый список машины показывал десять одинаковых строк «Не указано ·
/// Краснодар» и не отвечал ни на один вопрос, с которым в него заходят.
/// Здесь заперты обе причины: чужая подпись в заголовке и повтор региона
/// вместо времени.
final class TripRowTextTests: XCTestCase {

    private let when = Calendar(identifier: .gregorian)
        .date(from: DateComponents(year: 2026, month: 4, day: 18, hour: 17, minute: 41))!

    private func trip(title: String? = nil, custom: Bool = false,
                      region: String? = nil, km: Double = 20,
                      minutes: Double = 23) -> Trip {
        Trip(startDate: when, endDate: when.addingTimeInterval(minutes * 60),
             distance: km * 1000, title: title, titleIsCustom: custom, region: region)
    }

    // MARK: - Заголовок

    func testCustomNameWins() {
        XCTAssertEqual(TripRowText.title(trip(title: "На дачу", custom: true), .ru), "На дачу")
    }

    func testRegionStandsInForANamelessTrip() {
        XCTAssertEqual(TripRowText.title(trip(region: "Krasnodar Krai"), .ru),
                       RegionDisplay.localized("Krasnodar Krai", language: .ru))
    }

    func testNamelessAndRegionlessTripGetsTheGenericWordNotAPassportPlaceholder() {
        let t = TripRowText.title(trip(), .ru)
        XCTAssertEqual(t, AppStrings.tripTitle(.ru))
        XCTAssertNotEqual(t, AppStrings.vehicleNotSet(.ru),
                          "«Не указано» — подпись пустого поля паспорта, а не имя поездки")
    }

    /// Заголовок обязан совпадать с тем, что напишет сам экран поездки:
    /// иначе одна поездка называется в списке одним, а внутри другим.
    func testLadderMatchesTheTripScreen() {
        for t in [trip(title: "На дачу", custom: true), trip(region: "Krasnodar Krai"), trip()] {
            XCTAssertFalse(TripRowText.title(t, .ru).isEmpty)
        }
    }

    // MARK: - Когда

    func testWhenCarriesTimeOfDayAndDuration() {
        let s = TripRowText.when(trip(), .ru)
        XCTAssertTrue(s.contains("17:41"), "без часа две поездки одного дня неразличимы: \(s)")
        XCTAssertTrue(s.contains("23"), "в подписи потерялась длительность: \(s)")
    }

    /// Подпись не должна повторять заголовок — ровно этим список и был бесполезен.
    func testWhenIsNotTheRegionAgain() {
        let t = trip(region: "Krasnodar Krai")
        XCTAssertNotEqual(TripRowText.when(t, .ru), TripRowText.title(t, .ru))
    }

    // MARK: - Сколько

    func testShortTripDoesNotReadAsZero() {
        let s = TripRowText.km(trip(km: 0.4), .ru)
        XCTAssertTrue(s.hasPrefix("0,4"), "четыреста метров показаны как «\(s)»")
    }

    func testLongTripIsWhole() {
        XCTAssertTrue(TripRowText.km(trip(km: 137.4), .ru).hasPrefix("137"))
    }

    func testEveryLanguageProducesAllThreeParts() {
        for lang in LanguageManager.Language.allCases {
            let t = trip(region: "Krasnodar Krai")
            XCTAssertFalse(TripRowText.title(t, lang).isEmpty, "\(lang)")
            XCTAssertFalse(TripRowText.when(t, lang).isEmpty, "\(lang)")
            XCTAssertFalse(TripRowText.km(t, lang).isEmpty, "\(lang)")
        }
    }
}
