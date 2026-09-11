import XCTest
import CoreLocation
@testable import TripTrack

/// Правило поворота машинки на карте. Всё, что здесь проверяется, ловилось
/// раньше только глазами на устройстве: прокрутка через весь круг, дрожание на
/// стоянке и «нос дёргается на ровной дороге» выглядят одинаково «как-то не
/// так», и отличить их по видео нельзя.
final class CarHeadingPolicyTests: XCTestCase {

    private let frame: TimeInterval = 1.0 / 60

    // MARK: - Переход через ноль

    /// 359° → 1° это два градуса вправо, а не 358 налево.
    func testCrossingNorthGoesTheShortWayUp() {
        let delta = CarHeadingPolicy.shortestDelta(from: 359, to: 1)
        XCTAssertEqual(delta, 2, accuracy: 0.0001)
    }

    /// И обратно: 1° → 359° это два градуса влево.
    func testCrossingNorthGoesTheShortWayDown() {
        let delta = CarHeadingPolicy.shortestDelta(from: 1, to: 359)
        XCTAssertEqual(delta, -2, accuracy: 0.0001)
    }

    /// Шаг доведения через ноль не имеет права уехать в 180°: именно так
    /// машина и прокручивалась через весь круг на выезде с северной дороги.
    func testSmoothingNeverSpinsThroughTheWholeCircle() {
        var current: Double = 350
        for _ in 0..<120 {
            current = CarHeadingPolicy.smoothed(current: current, target: 10, dt: frame)
            // Весь путь идёт по короткой дуге 350 → 360/0 → 10, то есть угол
            // всегда либо у конца круга, либо у его начала. Юг посередине
            // означал бы, что маркер поехал длинной стороной.
            XCTAssertTrue(current >= 340 || current <= 20, "угол ушёл на \(current)")
        }
        XCTAssertEqual(CarHeadingPolicy.shortestDelta(from: current, to: 10), 0, accuracy: 2.5)
    }

    /// Ровно противоположный курс — единственный случай, где короткой дуги
    /// две. Знак не важен, важно что поворот конечный и не мечется.
    func testOppositeCourseTurnsTheWholeWayRound() {
        var current: Double = 0
        for _ in 0..<180 {
            current = CarHeadingPolicy.smoothed(current: current, target: 180, dt: frame)
        }
        XCTAssertEqual(CarHeadingPolicy.shortestDelta(from: current, to: 180), 0, accuracy: 2.5)
    }

    // MARK: - Заморозка

    /// Стоящая машина курс не меняет: у CoreLocation он на стоянке гуляет от
    /// шума позиции, и маркер вертелся бы волчком.
    func testParkedCarHoldsItsHeading() {
        XCTAssertNil(CarHeadingPolicy.liveCourse(course: 270, courseAccuracy: 5, rawSpeed: 0.3))
        XCTAssertEqual(
            CarHeadingPolicy.smoothed(current: 42, target: nil, dt: frame), 42, accuracy: 0.0001
        )
    }

    /// Заморозка не «подождать и повернуть»: сколько бы кадров ни прошло,
    /// угол остаётся тем же.
    func testFrozenHeadingSurvivesAThousandFrames() {
        var current: Double = 123
        for _ in 0..<1000 {
            current = CarHeadingPolicy.smoothed(current: current, target: nil, dt: frame)
        }
        XCTAssertEqual(current, 123, accuracy: 0.0001)
    }

    /// «Курса нет» у CoreLocation — это −1, и оно не должно превращаться в
    /// север ни здесь, ни где-либо ещё.
    func testUnknownCourseIsNotNorth() {
        XCTAssertNil(CarHeadingPolicy.liveCourse(course: -1, courseAccuracy: 5, rawSpeed: 20))
        XCTAssertNil(CarHeadingPolicy.liveCourse(course: nil, courseAccuracy: 5, rawSpeed: 20))
    }

    /// Точность курса — отдельные ворота: курс бывает, а веры ему нет.
    func testCourseWithoutAccuracyIsRefused() {
        XCTAssertNil(CarHeadingPolicy.liveCourse(course: 90, courseAccuracy: -1, rawSpeed: 20))
    }

    /// Едем — курс проходит как есть.
    func testDrivingCoursePassesThrough() {
        XCTAssertEqual(
            CarHeadingPolicy.liveCourse(course: 90, courseAccuracy: 5, rawSpeed: 20), 90
        )
    }

    /// Порог — ровно на границе, а не «где-то около»: парковка задним ходом на
    /// 3 км/ч курса не получает, выезд со двора на 6 км/ч получает.
    func testSpeedGateSitsWhereItIsDeclared() {
        XCTAssertNil(CarHeadingPolicy.liveCourse(course: 10, courseAccuracy: 5, rawSpeed: 0.83))
        XCTAssertEqual(
            CarHeadingPolicy.liveCourse(course: 10, courseAccuracy: 5, rawSpeed: 1.4), 10
        )
    }

    // MARK: - Мёртвая зона

    /// Поворот меньше мёртвой зоны не отрабатывается вовсе — на длине кузова
    /// это меньше полупикселя, но пересчёт каждый кадр видно как «дыхание».
    func testTinyWobbleIsIgnored() {
        let after = CarHeadingPolicy.smoothed(current: 100, target: 101.5, dt: frame)
        XCTAssertEqual(after, 100, accuracy: 0.0001)
    }

    /// А поворот за мёртвой зоной — отрабатывается, и в правильную сторону.
    func testTurnBeyondTheDeadZoneIsFollowed() {
        let after = CarHeadingPolicy.smoothed(current: 100, target: 130, dt: frame)
        XCTAssertGreaterThan(after, 100)
        XCTAssertLessThan(after, 130)
    }

    // MARK: - Потолок скорости поворота

    /// За кадр маркер не может повернуться больше, чем на свой потолок.
    /// Без этого скачок курса (тоннель) читается как подмена картинки.
    func testTurnRateIsCapped() {
        let after = CarHeadingPolicy.smoothed(current: 0, target: 179, dt: 0.5)
        XCTAssertLessThanOrEqual(
            abs(CarHeadingPolicy.shortestDelta(from: 0, to: after)),
            CarHeadingPolicy.maxTurnRate * 0.5 + 0.0001
        )
    }

    /// Потолок считается от ВРЕМЕНИ, а не от кадра: на 120 Гц поворот идёт с
    /// той же скоростью, что на 60, просто мельче шагами.
    func testTurnSpeedDoesNotDependOnFrameRate() {
        var at60: Double = 0
        for _ in 0..<60 { at60 = CarHeadingPolicy.smoothed(current: at60, target: 90, dt: 1.0 / 60) }
        var at120: Double = 0
        for _ in 0..<120 { at120 = CarHeadingPolicy.smoothed(current: at120, target: 90, dt: 1.0 / 120) }
        XCTAssertEqual(at60, at120, accuracy: 2.5)
    }

    // MARK: - Конус неуверенности

    /// Честный курс конуса не даёт: постоянная клякса на экране ничего не
    /// сообщает, а мешает всему.
    func testConfidentCourseDrawsNoCone() {
        XCTAssertNil(CarHeadingPolicy.coneHalfAngle(courseAccuracy: 5, rawSpeed: 20))
        XCTAssertNil(CarHeadingPolicy.coneHalfAngle(
            courseAccuracy: CarHeadingPolicy.coneThreshold, rawSpeed: 20
        ))
    }

    /// Раствор конуса — это и есть то, что сказал CoreLocation, а не наша
    /// выдумка о нём.
    func testConeRepeatsWhatTheFixSaid() throws {
        let cone = CarHeadingPolicy.coneHalfAngle(courseAccuracy: 35, rawSpeed: 20)
        XCTAssertEqual(try XCTUnwrap(cone), 35, accuracy: 0.0001)
    }

    /// Шире потолка конус не растёт: веер во полкарты — это уже не «примерно
    /// туда», а «не знаю», и говорить это надо неподвижным маркером.
    func testConeIsCapped() throws {
        let cone = CarHeadingPolicy.coneHalfAngle(courseAccuracy: 180, rawSpeed: 20)
        XCTAssertEqual(try XCTUnwrap(cone), CarHeadingPolicy.coneMaxHalfAngle, accuracy: 0.0001)
    }

    /// На стоянке конуса нет. Маркер там заморожен и держит последний
    /// достоверный угол — веер вокруг него обещал бы движение, которого нет.
    func testParkedCarHasNoCone() {
        XCTAssertNil(CarHeadingPolicy.coneHalfAngle(
            courseAccuracy: 45, rawSpeed: CarHeadingPolicy.minCourseSpeed - 0.01
        ))
    }

    /// Неизвестная точность (−1) — это «поля нет», а не «плохо». Рисовать по
    /// ней конус значило бы придумать неуверенность вместо того, чтобы её
    /// измерить.
    func testUnknownAccuracyGivesNoCone() {
        XCTAssertNil(CarHeadingPolicy.coneHalfAngle(courseAccuracy: -1, rawSpeed: 20))
    }

    // MARK: - Reduce Motion

    /// Поворот ОСТАЁТСЯ, уходит доводка: угол встаёт за один шаг, а не за
    /// полсекунды пружины. Apple стрелку курса при Reduce Motion тоже не
    /// выключает — это информация, а не украшение.
    func testReduceMotionTurnsInstantlyButStillTurns() {
        let angle = CarHeadingPolicy.smoothed(current: 0, target: 90, dt: frame, instant: true)
        XCTAssertEqual(angle, 90, accuracy: 0.0001)
    }

    /// Мгновенный поворот идёт мимо потолка скорости, но не мимо мёртвой
    /// зоны: она не про плавность, а про то, чтобы маркер не дышал на ровной
    /// дороге.
    func testReduceMotionKeepsTheDeadZone() {
        let angle = CarHeadingPolicy.smoothed(current: 10, target: 11, dt: frame, instant: true)
        XCTAssertEqual(angle, 10, accuracy: 0.0001)
    }

    /// И заморозку: курса нет — угол не меняется ни с доводкой, ни без неё.
    func testReduceMotionStillFreezesWithoutACourse() {
        XCTAssertEqual(
            CarHeadingPolicy.smoothed(current: 137, target: nil, dt: frame, instant: true),
            137, accuracy: 0.0001
        )
    }

    // MARK: - Экранный угол

    /// Карта, повёрнутая пальцем, уносит с собой дорогу — маркер обязан
    /// повернуться вместе с ней.
    func testScreenAngleSubtractsTheCamera() {
        XCTAssertEqual(CarHeadingPolicy.screenAngle(course: 90, cameraHeading: 30), 60, accuracy: 0.0001)
        XCTAssertEqual(CarHeadingPolicy.screenAngle(course: 10, cameraHeading: 30), 340, accuracy: 0.0001)
    }

    /// В режиме «по курсу» камера сама встаёт носом по движению — и маркер
    /// смотрит вверх без отдельной ветки на этот случай.
    func testFollowWithHeadingPointsTheCarUp() {
        XCTAssertEqual(CarHeadingPolicy.screenAngle(course: 217, cameraHeading: 217), 0, accuracy: 0.0001)
    }

    // MARK: - Курс по маршруту

    /// Упреждение смотрит на ДЕСЯТКИ метров вперёд, а не на соседний кадр:
    /// два соседних кадра различаются меньше, чем квант хранения полилинии.
    func testCourseAlongRouteLooksAhead() {
        // Строго на восток, шаг ~7 м.
        let coords = (0..<40).map {
            CLLocationCoordinate2D(latitude: 45, longitude: 39 + Double($0) * 0.00009)
        }
        let course = CarHeadingPolicy.courseAlongRoute(from: coords[0], passed: 0, in: coords)
        XCTAssertEqual(course ?? -1, 90, accuracy: 1)
    }

    /// Шум ниже кванта хранения курса не даёт: соседняя точка в сантиметрах —
    /// это не поворот, это одинарная точность.
    func testQuantisationNoiseGivesNoCourse() {
        let here = CLLocationCoordinate2D(latitude: 45, longitude: 39)
        let barelyMoved = CLLocationCoordinate2D(latitude: 45, longitude: 39.000001)
        XCTAssertNil(CarHeadingPolicy.courseAlongRoute(
            from: here, passed: 0, in: [here, barelyMoved]
        ))
    }

    /// Метры набираются ВДОЛЬ трека. На шпильке точка в двенадцати метрах пути
    /// лежит в трёх по прямой, и счёт по прямой перепрыгнул бы поворот целиком,
    /// показав нос назад ещё до входа в него.
    func testLookaheadWalksTheRouteAndNotTheStraightLine() {
        // Пять метров на север, ещё пять, два вправо — и обратно на юг. Конец
        // этой шпильки лежит в ДВУХ метрах от начала по прямой и в двадцати
        // двух по дороге: счёт по прямой не нашёл бы впереди ничего дальше
        // упреждения и показал бы нос вбок, на выход из шпильки.
        let start = CLLocationCoordinate2D(latitude: 45, longitude: 39)
        let coords = [
            start,
            CLLocationCoordinate2D(latitude: 45.000045, longitude: 39),
            CLLocationCoordinate2D(latitude: 45.000090, longitude: 39),
            CLLocationCoordinate2D(latitude: 45.000090, longitude: 39.000025),
            CLLocationCoordinate2D(latitude: 45.000045, longitude: 39.000025),
            CLLocationCoordinate2D(latitude: 45.000000, longitude: 39.000025),
        ]
        let course = CarHeadingPolicy.courseAlongRoute(from: start, passed: 0, in: coords)
        // Нос всё ещё смотрит вперёд по дороге, то есть на север, а не вбок.
        XCTAssertNotNil(course)
        XCTAssertLessThan(abs(CarHeadingPolicy.shortestDelta(from: course ?? 0, to: 0)), 60)
    }

    /// Финиш: маршрут кончился ближе упреждения — целимся в последнюю точку,
    /// и машина замирает так, как приехала.
    func testEndOfRouteStillGivesTheLastDirection() {
        let coords = [
            CLLocationCoordinate2D(latitude: 45, longitude: 39),
            CLLocationCoordinate2D(latitude: 45.00005, longitude: 39),
        ]
        let course = CarHeadingPolicy.courseAlongRoute(from: coords[0], passed: 0, in: coords)
        XCTAssertEqual(course ?? -1, 0, accuracy: 1)
    }

    /// Прошли последнюю точку — впереди ничего, держим прежний угол.
    func testPastTheLastPointThereIsNothingAhead() {
        let last = CLLocationCoordinate2D(latitude: 45, longitude: 39)
        let coords = [CLLocationCoordinate2D(latitude: 44.999, longitude: 39), last]
        XCTAssertNil(CarHeadingPolicy.courseAlongRoute(from: last, passed: 1, in: coords))
    }

    // MARK: - Нормализация

    func testAnglesComeBackInsideTheCircle() {
        XCTAssertEqual(CarHeadingPolicy.normalized(-10), 350, accuracy: 0.0001)
        XCTAssertEqual(CarHeadingPolicy.normalized(370), 10, accuracy: 0.0001)
        XCTAssertEqual(CarHeadingPolicy.normalized(360), 0, accuracy: 0.0001)
    }

    // MARK: - Курс из CoreLocation

    /// Невалидный курс приезжает как «не знаю», а не как «строго на север» —
    /// мина, из-за которой маркер на парковке смотрел бы на север.
    func testLocationUpdateKeepsUnknownCourseUnknown() {
        let unknown = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 45, longitude: 39),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            course: -1, speed: 0, timestamp: Date()
        )
        XCTAssertNil(LocationUpdate.from(unknown).course)
        // И обратно в CLLocation — тоже «не знаю», а не 0.
        XCTAssertLessThan(LocationUpdate.from(unknown).toCLLocation().course, 0)
    }

    func testLocationUpdateKeepsAKnownCourse() {
        let known = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 45, longitude: 39),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            course: 137, speed: 20, timestamp: Date()
        )
        XCTAssertEqual(LocationUpdate.from(known).course ?? -1, 137, accuracy: 0.0001)
    }
}
