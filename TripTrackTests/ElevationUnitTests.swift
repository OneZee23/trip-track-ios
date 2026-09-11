import XCTest
@testable import TripTrack

/// Высота идёт той же настройкой, что и расстояние.
///
/// «26.2 mi · ↑ 640 m» — тот же смешанный грех, что «79 mi · 68 км/ч», и
/// заметен он даже сильнее: два числа стоят в одной строке. Поэтому футы
/// приезжают вместе с милями, а не отдельной галочкой.
///
/// Ловушка, ради которой этот файл существует, не в конверсии, а в ИМЕНИ: до
/// 0.6.7 высоту печатала `GarageFormat.odometer` — функция про пробег, — и
/// конверсия, встроенная туда «заодно», увезла бы метры в мили ×0.621 молча,
/// без единой ошибки компиляции. Здесь заперты все места показа высоты сразу:
/// у каждого проверяется, что метры стали ФУТАМИ, а не милями.
final class ElevationUnitTests: XCTestCase {

    private let when = Calendar(identifier: .gregorian)
        .date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 14, minute: 5))!

    private func trip(elevation: Double, km: Double = 316) -> Trip {
        Trip(startDate: when, endDate: when.addingTimeInterval(3600),
             distance: km * 1000, elevation: elevation)
    }

    /// 640 м — это 2 100 футов. Если где-то выйдет ≈398, значит высоту
    /// поделили на милю: ровно та поломка, от которой у `Measure` отдельная
    /// функция.
    private func assertFeetNotMiles(_ line: String, file: StaticString = #filePath,
                                    line number: UInt = #line) {
        XCTAssertTrue(line.contains("2") && (line.contains("100") || line.contains("099")),
                      "не футы: \(line)", file: file, line: number)
        XCTAssertFalse(line.contains("398"), "метры поделили на милю: \(line)",
                       file: file, line: number)
        XCTAssertFalse(line.contains(" m") || line.contains(" м"),
                       "в футах осталась метрическая подпись: \(line)",
                       file: file, line: number)
    }

    // MARK: - Строка поездки в гараже

    func testGarageRowFollowsTheUnit() {
        let t = trip(elevation: 640)
        XCTAssertEqual(TripRowText.elevation(t, .ru, unit: .km), "↑ 640 м")
        assertFeetNotMiles(TripRowText.elevation(t, .en, unit: .miles))
    }

    // MARK: - Личное число значка

    /// «Проедьте 1000 м набора» — это правило игры, и оно метрическое у всех.
    /// А вот «набрал 640 м» — личное число, и его читают в своём.
    func testBadgeRecordValueFollowsTheUnit() {
        let goat = Badge.all.first { $0.id == "mountain_goat" }!
        let t = trip(elevation: 640)
        XCTAssertEqual(goat.recordValue(for: t, unit: .km, language: .ru), "640 м")
        assertFeetNotMiles(goat.recordValue(for: t, unit: .miles, language: .en) ?? "")
    }

    /// Значок «выше облаков» читает пик по точкам трека, а не поле поездки —
    /// поэтому у него своя ветка и свой шанс остаться метрическим.
    func testBadgePeakAltitudeFollowsTheUnit() {
        let clouds = Badge.all.first { $0.id == "above_clouds" }!
        var t = trip(elevation: 640)
        t.trackPoints = [
            TrackPoint(latitude: 43.1, longitude: 44.6, altitude: 640, timestamp: when)
        ]
        XCTAssertEqual(clouds.recordValue(for: t, unit: .km, language: .ru), "640 м")
        assertFeetNotMiles(clouds.recordValue(for: t, unit: .miles, language: .en) ?? "")
    }

    // MARK: - График высоты

    /// Подпись под пальцем: «186 м · 14:05». Обе половины строки — свои
    /// единицы: высота сверху, расстояние снизу, и обе следуют одной настройке.
    func testChartReadoutFollowsTheUnit() {
        let pt = DetailChartPoint(id: 0, x: 212, y: 640, date: when)
        XCTAssertEqual(
            TripDetailFormat.chartAltitudeReadout(pt, unit: .km, lang: .ru), "640 м · 14:05")
        let feet = TripDetailFormat.chartAltitudeReadout(pt, unit: .miles, lang: .en)
        XCTAssertTrue(feet.hasSuffix("· 14:05"), "потерялось время: \(feet)")
        assertFeetNotMiles(String(feet.dropLast("· 14:05".count)))
    }
}
