import XCTest
import CoreLocation
@testable import TripTrack

/// Сборка вписанной рукой поездки — время, километры, скорость.
///
/// Фикстура — двести точек по дуге, то есть настоящая линия маршрута, а не
/// три точки, на которых сойдётся любая формула. Половина проверок здесь про
/// то, что расстояние приходит ИЗ `TripDistanceGate`, а не считается вторым
/// способом: разойдясь однажды, эти два числа не сойдутся никогда — ровно та
/// поломка, из-за которой в 0.6.5 четыре подсчёта свели в один.
final class ManualTripBuilderTests: XCTestCase {

    /// Двести точек примерно по 60 м друг от друга — около двенадцати
    /// километров. Шаг заведомо больше пятиметрового: на более частых точках
    /// гейт начал бы их пропускать, и тест мерил бы не то, что сторожит.
    private func fixture(count: Int = 200) -> [CLLocationCoordinate2D] {
        (0..<count).map { i in
            let t = Double(i)
            return CLLocationCoordinate2D(
                latitude: 45.0 + t * 0.0005,
                longitude: 39.0 + sin(t / 20) * 0.0004
            )
        }
    }

    private func draft(
        count: Int = 200, duration: TimeInterval = 3600, title: String? = nil
    ) -> ManualTripBuilder.Draft {
        ManualTripBuilder.Draft(
            coordinates: fixture(count: count),
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            duration: duration,
            vehicleId: nil,
            title: title
        )
    }

    // MARK: - Время

    func testTimestampsAreMonotoneAndSpanExactlyTheDuration() throws {
        let d = draft()
        let trip = try XCTUnwrap(ManualTripBuilder.build(d))

        XCTAssertEqual(trip.trackPoints.count, 200)
        let stamps = trip.trackPoints.map(\.timestamp)
        for (a, b) in zip(stamps, stamps.dropFirst()) {
            XCTAssertLessThan(a, b, "время обязано идти только вперёд")
        }
        XCTAssertEqual(stamps.first, d.startDate)
        // Последняя точка попадает РОВНО в конец: иначе длительность поездки и
        // её последняя отметка времени разошлись бы на шаг.
        XCTAssertEqual(
            try XCTUnwrap(stamps.last).timeIntervalSince(d.startDate), d.duration, accuracy: 0.001)
        XCTAssertEqual(trip.endDate, d.startDate.addingTimeInterval(d.duration))
    }

    func testStepsAreEven() throws {
        let trip = try XCTUnwrap(ManualTripBuilder.build(draft()))
        let stamps = trip.trackPoints.map(\.timestamp)
        let steps = zip(stamps, stamps.dropFirst()).map { $1.timeIntervalSince($0) }
        let first = try XCTUnwrap(steps.first)
        for step in steps {
            XCTAssertEqual(step, first, accuracy: 0.001, "шаг обязан быть одинаковым")
        }
    }

    // MARK: - Километры

    /// Главная проверка версии: расстояние поездки — это ровно то, что даёт
    /// общая функция по тем же точкам с тем же временем. Допуск процент, но
    /// сходится оно побитово.
    func testDistanceComesFromTheSharedGate() throws {
        let d = draft()
        let trip = try XCTUnwrap(ManualTripBuilder.build(d))

        let stamps = ManualTripBuilder.timestamps(
            count: d.coordinates.count, startDate: d.startDate, duration: d.duration)
        let expected = TripDistanceGate.totalDistance(
            zip(d.coordinates, stamps).map {
                TripDistanceGate.Sample(latitude: $0.0.latitude,
                                        longitude: $0.0.longitude, timestamp: $0.1)
            }
        )

        XCTAssertGreaterThan(expected, 1000, "фикстура обязана быть настоящей дорогой")
        XCTAssertEqual(trip.distance, expected, accuracy: expected * 0.01)
    }

    // MARK: - Скорость

    func testSpeedIsConstantAndEqualsTheAverage() throws {
        let d = draft()
        let trip = try XCTUnwrap(ManualTripBuilder.build(d))

        let expected = trip.distance / d.duration
        for point in trip.trackPoints {
            XCTAssertEqual(point.speed, expected, accuracy: 0.0001)
        }
        XCTAssertEqual(trip.averageSpeed, expected, accuracy: 0.0001)
        // Максимума у постоянной скорости нет — и печатать вместо него ноль
        // тоже нельзя: ноль читается как «не измерили».
        XCTAssertEqual(trip.maxSpeed, trip.averageSpeed)
    }

    // MARK: - Остальное

    func testSourceIsManualAndElevationIsZero() throws {
        let trip = try XCTUnwrap(ManualTripBuilder.build(draft()))
        XCTAssertEqual(trip.source, .manual)
        XCTAssertEqual(trip.elevation, 0)
        XCTAssertTrue(trip.trackPoints.allSatisfy { $0.altitude == 0 })
        // Приватная, как и записанная: публикует владелец, а не сборка.
        XCTAssertTrue(trip.isPrivate)
    }

    func testCourseIsFilledInForEveryPoint() throws {
        let trip = try XCTUnwrap(ManualTripBuilder.build(draft()))
        for point in trip.trackPoints {
            XCTAssertGreaterThanOrEqual(point.course, 0, "курс читают места и реплей")
            XCTAssertLessThan(point.course, 360)
        }
    }

    func testNameIsCustomOnlyWhenSomethingWasTyped() throws {
        let named = try XCTUnwrap(ManualTripBuilder.build(draft(title: "До моря")))
        XCTAssertEqual(named.title, "До моря")
        XCTAssertTrue(named.titleIsCustom)

        let blank = try XCTUnwrap(ManualTripBuilder.build(draft(title: "   ")))
        XCTAssertNil(blank.title, "пробелы — это не имя")
        XCTAssertFalse(blank.titleIsCustom)
    }

    func testRefusesWhatCannotBeATrip() {
        XCTAssertNil(ManualTripBuilder.build(draft(count: 1)))
        XCTAssertNil(ManualTripBuilder.build(draft(duration: 0)))
    }

    // MARK: - Нижняя граница длительности

    /// Самая тихая ловушка версии: на слишком коротком времени
    /// `TripDistanceGate` объявляет КАЖДЫЙ отрезок телепортом, и поездка
    /// ложится в базу с нулём километров — молча, без единой ошибки, и дальше
    /// её забирает фильтр мусорных. Отсюда `feasibleDuration`, и отсюда же
    /// этот тест: он показывает обе стороны границы.
    func testATooShortDurationCollapsesTheDistanceToZero() throws {
        let d = draft(duration: 60)
        let trip = try XCTUnwrap(ManualTripBuilder.build(d))
        XCTAssertEqual(trip.distance, 0, accuracy: 0.001,
                       "триста километров в час гейт не пропускает, и это правильно")
        XCTAssertTrue(trip.isJunk, "поэтому такую длительность лист и не даёт выбрать")
    }

    func testTheFeasibleDurationKeepsEveryMetre() throws {
        let coords = fixture()
        let straight = TripDistanceGate.totalDistance(
            coords.map { TripDistanceGate.Sample(
                latitude: $0.latitude, longitude: $0.longitude, timestamp: nil) }
        )
        let floor = ManualTripBuilder.feasibleDuration(forRouteMetres: straight)
        let trip = try XCTUnwrap(ManualTripBuilder.build(draft(duration: floor)))

        XCTAssertEqual(trip.distance, straight, accuracy: straight * 0.01)
        XCTAssertFalse(trip.isJunk)
    }

    /// Верхняя граница обязана ПЕРЕКРЫВАТЬ любой маршрут, который отдаст
    /// `MKDirections` по дорогам. Сутки её не перекрывали: у дороги длиннее
    /// 4 320 км пол поднимался выше потолка, и «Создать» выключалась навсегда
    /// без единого слова о причине.
    func testTheCeilingCoversAnyRoadRouteOnEarth() {
        // Самая длинная автомобильная дорога мира — Панамерикана, около
        // 30 000 км; `MKDirections` по дорогам большего не вернёт.
        let panamerican: Double = 30_000_000
        XCTAssertLessThanOrEqual(
            ManualTripBuilder.feasibleDuration(forRouteMetres: panamerican),
            ManualTripBuilder.maximumDuration,
            "потолок длительности ниже пола — кнопка «Создать» выключится навсегда"
        )
    }

    /// И обратная граница: если маршрут ВСЁ-ТАКИ длиннее потолка, пол
    /// честно оказывается выше — это то состояние, под которое на экране
    /// написана отдельная строка, а не молча выключенная кнопка.
    func testAnImpossiblyLongRouteIsDetectableRatherThanSilent() {
        let absurd = ManualTripBuilder.maximumDuration
            * ManualTripBuilder.maxPlausibleAverage * 2
        XCTAssertGreaterThan(
            ManualTripBuilder.feasibleDuration(forRouteMetres: absurd),
            ManualTripBuilder.maximumDuration
        )
    }

    func testTheFeasibleDurationNeverGoesBelowTheFloor() {
        XCTAssertEqual(ManualTripBuilder.feasibleDuration(forRouteMetres: 0),
                       ManualTripBuilder.minimumDuration)
        XCTAssertEqual(ManualTripBuilder.feasibleDuration(forRouteMetres: 100),
                       ManualTripBuilder.minimumDuration,
                       "у короткого маршрута побеждает общий пол в минуту")
    }
}
