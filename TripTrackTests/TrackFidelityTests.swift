import XCTest
import CoreData
import CoreLocation
@testable import TripTrack

/// Точность трека (0.6.5).
///
/// Задача версии: итоговая карта должна показывать то, что было — повороты,
/// круги, заезды по дворам, — не срезая углы. Способ: писать форму трека чаще,
/// а километры оставить при прежнем правиле.
///
/// До 0.6.5 «точка записана» и «километры посчитаны» были одним событием: пять
/// метров — и то, и другое. Пять метров машина проходит на трассе за пятую долю
/// секунды и во дворе за три с половиной, так что бюджет точек тратился там,
/// где дорога прямая, и кончался там, где всё решается: разворот в три приёма
/// описывался двумя точками. Это и есть «срезанный угол» — рисовать было нечем.
///
/// Разъехавшись, эти два счёта стали опасны друг для друга: сложи плотные
/// точки подряд — и одометр вырастет от одного шума. Поэтому здесь проверяется
/// не только «стало детальнее», но и «цифры не поехали» — половина тестов
/// именно про второе.
final class TrackFidelityTests: XCTestCase {

    // MARK: - Инструменты

    /// Свой генератор вместо системного: тест обязан падать и проходить
    /// одинаково каждый раз, иначе он не тест, а лотерея.
    private struct Noise {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((state >> 33) % 10_000) / 10_000.0 * 2 - 1  // −1…1
        }
    }

    private static let metersPerDegree = 111_320.0
    private static let origin = CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975)

    /// Точка в метрах от начала координат — так тесты читаются как чертёж.
    private func fix(
        east: Double,
        north: Double,
        speed: Double,
        course: Double,
        after seconds: TimeInterval,
        accuracy: Double = 8
    ) -> CLLocation {
        let lat = Self.origin.latitude + north / Self.metersPerDegree
        let lon = Self.origin.longitude + east / (Self.metersPerDegree * cos(Self.origin.latitude * .pi / 180))
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: 100,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 3,
            course: course,
            speed: speed,
            timestamp: Date(timeIntervalSince1970: 1_780_000_000 + seconds)
        )
    }

    private func makeManager() -> (TripManager, PersistenceController) {
        let pc = PersistenceController(inMemory: true)
        let manager = TripManager(locationManager: LocationManager(), persistenceController: pc)
        manager.startTrip(vehicleId: UUID())
        return (manager, pc)
    }

    private func storedPoints(_ pc: PersistenceController) -> [TrackPointEntity] {
        let request: NSFetchRequest<TrackPointEntity> = TrackPointEntity.fetchRequest()
        let points = (try? pc.container.viewContext.fetch(request)) ?? []
        return points.sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
    }

    private func recordedDistance(_ pc: PersistenceController) -> Double {
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        return ((try? pc.container.viewContext.fetch(request))?.first)?.distance ?? 0
    }

    /// Как поездка выглядела бы для СТАРОЙ версии: система отдавала фикс только
    /// когда телефон отъехал на пять метров, поэтому медленный ход она
    /// прореживала сама. Прогнать один и тот же маршрут через оба потока —
    /// единственный честный способ сравнить «до» и «после».
    private func thinnedTo5m(_ fixes: [CLLocation]) -> [CLLocation] {
        var kept: [CLLocation] = []
        for fix in fixes {
            guard let last = kept.last else { kept.append(fix); continue }
            if fix.distance(from: last) >= 5 { kept.append(fix) }
        }
        return kept
    }

    // MARK: - Маршруты

    /// Прямая на 10 м/с (36 км/ч) с шумом GPS.
    private func straightDrive(seconds: Int, noise amplitude: Double) -> [CLLocation] {
        var rng = Noise(seed: 42)
        return (0...seconds).map { t in
            fix(east: rng.next() * amplitude,
                north: Double(t) * 10 + rng.next() * amplitude,
                speed: 10, course: 0, after: Double(t))
        }
    }

    /// Самый медленный манёвр: 3 км/ч, парковка задним ходом.
    private func parkingCrawl(noise amplitude: Double) -> [CLLocation] {
        var rng = Noise(seed: 21)
        let speed = 0.83  // 3 км/ч
        return (1...60).map { t in
            fix(east: rng.next() * amplitude,
                north: Double(t) * speed + rng.next() * amplitude,
                speed: speed, course: 0, after: Double(t))
        }
    }

    /// Двор: 5 км/ч, четыре прямых угла — то, ради чего всё затевалось.
    private func courtyardManeuver(noise amplitude: Double) -> [CLLocation] {
        var rng = Noise(seed: 7)
        let speed = 1.39  // 5 км/ч
        var fixes: [CLLocation] = []
        var east = 0.0, north = 0.0, t = 0.0
        let legs: [(dE: Double, dN: Double, course: Double)] = [
            (0, 1, 0), (1, 0, 90), (0, -1, 180), (-1, 0, 270)
        ]
        for leg in legs {
            for _ in 0..<20 {   // 20 секунд на сторону ≈ 28 метров
                east += leg.dE * speed
                north += leg.dN * speed
                t += 1
                fixes.append(fix(east: east + rng.next() * amplitude,
                                 north: north + rng.next() * amplitude,
                                 speed: speed, course: leg.course, after: t))
            }
        }
        return fixes
    }

    // MARK: - Цифры не поехали

    /// Главная проверка версии. Один и тот же маршрут, поданный старым редким
    /// потоком и новым плотным, обязан дать один и тот же одометр.
    ///
    /// Если это когда-нибудь перестанет выполняться — значит километры поехали
    /// за формой, шум начал копиться посекундно, и мы вернулись в 0.5.7, где
    /// пробег рос сам по себе.
    func testDenseRecordingDoesNotChangeTheOdometer() {
        let route = straightDrive(seconds: 200, noise: 2.0)  // 2000 м по земле

        let (dense, densePC) = makeManager()
        route.forEach(dense.handleNewLocation)
        let denseKm = recordedDistance(densePC)

        let (sparse, sparsePC) = makeManager()
        thinnedTo5m(route).forEach(sparse.handleNewLocation)
        let sparseKm = recordedDistance(sparsePC)

        XCTAssertEqual(denseKm, sparseKm, accuracy: max(sparseKm * 0.02, 20),
                       "одометр разошёлся со старым: \(Int(denseKm)) м против \(Int(sparseKm)) м")
        XCTAssertEqual(denseKm, 2000, accuracy: 100,
                       "плотная запись накопила шум: \(Int(denseKm)) м вместо 2000")
    }

    /// То же на медленном ходу, где разница в плотности максимальная, а
    /// отношение шума к пройденному — самое злое.
    func testTheOdometerHoldsAtCourtyardSpeed() {
        let route = courtyardManeuver(noise: 1.5)
        let ground = 4 * 20 * 1.39  // 111 м

        let (dense, densePC) = makeManager()
        route.forEach(dense.handleNewLocation)

        XCTAssertEqual(recordedDistance(densePC), ground, accuracy: ground * 0.2,
                       "во дворе одометр ушёл: \(Int(recordedDistance(densePC))) м вместо \(Int(ground))")
    }

    /// Стоящая машина не пишет ни точек, ни метров.
    ///
    /// Порог «машина едет» подобран именно здесь: опусти его ниже — и дрожание
    /// GPS на парковке начнёт рисовать кляксу на месте стоянки, а этот тест
    /// покраснеет первым.
    func testAParkedCarWritesNothing() {
        var rng = Noise(seed: 99)
        let (manager, pc) = makeManager()

        for t in 0...120 {
            manager.handleNewLocation(
                fix(east: rng.next() * 3, north: rng.next() * 3,
                    speed: 0, course: -1, after: Double(t))
            )
        }

        XCTAssertEqual(recordedDistance(pc), 0, accuracy: 0.001,
                       "стояние принесло километры")
        XCTAssertLessThanOrEqual(storedPoints(pc).count, 2,
                                 "стояние нарисовало кляксу из \(storedPoints(pc).count) точек")
    }

    // MARK: - Стало детальнее

    /// Двор рисуется втрое подробнее. Это и есть заявленная польза версии:
    /// разворот, которому раньше доставалось две точки, теперь получает
    /// достаточно, чтобы его было видно.
    func testTheCourtyardIsRecordedFarDenser() {
        let route = courtyardManeuver(noise: 1.0)

        let (dense, densePC) = makeManager()
        route.forEach(dense.handleNewLocation)
        let denseCount = storedPoints(densePC).count

        let (sparse, sparsePC) = makeManager()
        thinnedTo5m(route).forEach(sparse.handleNewLocation)
        let sparseCount = storedPoints(sparsePC).count

        XCTAssertGreaterThan(Double(denseCount), Double(sparseCount) * 2.5,
                             "во дворе плотность почти не выросла: \(denseCount) против \(sparseCount)")
    }

    /// Парковка задним ходом на трёх километрах в час — самое медленное, что
    /// человек делает за рулём, и ровно то, что просили видеть на карте. Порог
    /// «машина едет» обязан пропускать её: поставь он планку выше — и заезд в
    /// свой двор снова описывался бы двумя точками.
    func testTheSlowestParkingCrawlIsRecordedToo() {
        let route = parkingCrawl(noise: 1.0)

        let (dense, densePC) = makeManager()
        route.forEach(dense.handleNewLocation)

        let (sparse, sparsePC) = makeManager()
        thinnedTo5m(route).forEach(sparse.handleNewLocation)

        XCTAssertGreaterThan(Double(storedPoints(densePC).count),
                             Double(storedPoints(sparsePC).count) * 2,
                             "парковка пишется не плотнее прежнего: \(storedPoints(densePC).count) против \(storedPoints(sparsePC).count)")
    }

    /// На трассе плотность НЕ растёт: там пятиметровый порог и так отдавал
    /// точку в секунду, и удорожать нечего. Если этот тест однажды покраснеет,
    /// значит трафик и батарея выросли впустую.
    func testTheMotorwayDoesNotGetHeavier() {
        var rng = Noise(seed: 5)
        let route = (0...120).map { t in
            fix(east: rng.next(), north: Double(t) * 25, speed: 25, course: 0, after: Double(t))
        }

        let (dense, densePC) = makeManager()
        route.forEach(dense.handleNewLocation)

        let (sparse, sparsePC) = makeManager()
        thinnedTo5m(route).forEach(sparse.handleNewLocation)

        XCTAssertLessThanOrEqual(storedPoints(densePC).count,
                                 storedPoints(sparsePC).count + 2,
                                 "на трассе точек стало заметно больше — это лишний вес")
    }

    /// Потолок держится, даже если система вдруг зачастит: десять фиксов в
    /// секунду не дают больше трёх точек в ту же секунду.
    func testThePointRateIsCapped() {
        let (manager, pc) = makeManager()
        var course = 0.0

        for i in 0..<200 {                    // 20 секунд по 10 Гц
            let t = Double(i) / 10.0
            course = (course + 30).truncatingRemainder(dividingBy: 360)  // вертится всё время
            manager.handleNewLocation(
                fix(east: sin(t) * 3, north: t * 3, speed: 3, course: course, after: t)
            )
        }

        let perSecond = Dictionary(grouping: storedPoints(pc)) {
            Int(($0.timestamp ?? .distantPast).timeIntervalSince1970)
        }
        let worst = perSecond.values.map(\.count).max() ?? 0
        XCTAssertLessThanOrEqual(worst, 3, "за одну секунду записалось \(worst) точек")
    }

    // MARK: - Разница курсов

    /// 359° и 1° — соседи, а не противоположности. Наивное вычитание дало бы
    /// 358° и объявило бы манёвром езду по прямой.
    func testCourseDeltaCrossesNorth() {
        XCTAssertEqual(GeometryUtils.courseDelta(359, 1), 2, accuracy: 0.001)
        XCTAssertEqual(GeometryUtils.courseDelta(1, 359), 2, accuracy: 0.001)
        XCTAssertEqual(GeometryUtils.courseDelta(10, 190), 180, accuracy: 0.001)
        XCTAssertEqual(GeometryUtils.courseDelta(-1, 90), 0, accuracy: 0.001,
                       "неизвестный курс — это не поворот")
    }

    // MARK: - Один счёт километров на всех

    /// Расстояние считают три места: запись, финализация поездки и
    /// пост-обработка, — причём последние две ПЕРЕЗАПИСЫВАЮТ результат первой.
    /// Пока точки лежали в пяти метрах, три копии цикла давали одно и то же; на
    /// плотных точках они разъезжаются, и побеждает та, что отработала
    /// последней. Отсюда общая функция — и этот тест на её шаг.
    func testDistanceIsCountedByTheFiveMetreStep() {
        // Двести точек по метру: путь пройден шагами меньше порога, и всё
        // равно обязан сложиться целиком. Хвост короче шага в счёт не идёт —
        // так было и до 0.6.5, где точка вообще не появлялась, пока машина не
        // отъедет на пять метров; на поездке это теряет метры, а не километры.
        let metres = 200
        let samples = (0...metres).map { i in
            TripDistanceGate.Sample(
                latitude: Self.origin.latitude + Double(i) / Self.metersPerDegree,
                longitude: Self.origin.longitude,
                timestamp: Date(timeIntervalSince1970: 1_780_000_000 + Double(i))
            )
        }
        let walked = TripDistanceGate.totalDistance(samples)
        let straight = CLLocation(latitude: samples[0].latitude, longitude: samples[0].longitude)
            .distance(from: CLLocation(latitude: samples[metres].latitude,
                                       longitude: samples[metres].longitude))
        XCTAssertEqual(walked, straight, accuracy: TripDistanceGate.minStep + 1,
                       "шаг обязан набирать полный путь, а не терять его")
        XCTAssertLessThanOrEqual(walked, straight,
                                 "шаг не имеет права насчитать БОЛЬШЕ, чем пройдено")

        // Дрожание на месте в пределах шага не приносит ничего.
        var rng = Noise(seed: 3)
        let jitter = (0...60).map { i in
            TripDistanceGate.Sample(
                latitude: Self.origin.latitude + rng.next() * 2 / Self.metersPerDegree,
                longitude: Self.origin.longitude + rng.next() * 2 / Self.metersPerDegree,
                timestamp: Date(timeIntervalSince1970: 1_780_000_000 + Double(i))
            )
        }
        XCTAssertLessThan(TripDistanceGate.totalDistance(jitter), 15,
                          "шум на месте пролез в километры")
    }
}
