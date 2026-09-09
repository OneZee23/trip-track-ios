import XCTest
import CoreLocation
@testable import TripTrack

/// Подсказка «Похоже на путешествие»: чистое правило «ночь не дома».
///
/// Половина тестов тут — про то, чего подсказка НЕ предлагает. Ложная
/// подсказка дороже пропущенной: пропущенную человек соберёт руками
/// мультивыбором, а на ложную он отвечает «нет» и перестаёт верить экрану.
final class JourneySuggesterTests: XCTestCase {
    // Полночь по местному, а не сырой epoch: правило про «02:00 местного»
    // иначе проверялось бы на случайном часе суток (см. JourneyAggregateTests).
    private let t0 = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))
    private let krd = CLLocationCoordinate2D(latitude: 45.03, longitude: 38.98)
    private let vld = CLLocationCoordinate2D(latitude: 43.02, longitude: 44.68)
    private let tbs = CLLocationCoordinate2D(latitude: 41.72, longitude: 44.79)
    /// 80 км строго на север от дома: дальше `awayRadius`, но ночь — дома.
    private let work = CLLocationCoordinate2D(latitude: 45.75, longitude: 38.98)
    /// 100 км на север: дача, куда ездят каждые выходные с ночёвкой.
    private let dacha = CLLocationCoordinate2D(latitude: 45.93, longitude: 38.98)
    private let dzhubga = CLLocationCoordinate2D(latitude: 44.32, longitude: 38.70)

    private func trip(day: Int, hour: Double, from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                      km: Double, hours: Double) -> Trip {
        let start = t0.addingTimeInterval(Double(day) * 86_400 + hour * 3_600)
        let pts = [TrackPoint(latitude: from.latitude, longitude: from.longitude, timestamp: start),
                   TrackPoint(latitude: to.latitude, longitude: to.longitude, timestamp: start.addingTimeInterval(hours * 3_600))]
        return Trip(id: UUID(), startDate: start, endDate: start.addingTimeInterval(hours * 3_600),
                    distance: km * 1_000, maxSpeed: 30, averageSpeed: 25, trackPoints: pts, photos: [],
                    title: nil, fuelUsed: 0, elevation: 0, region: nil, isPrivate: true,
                    earnedBadgeIds: [], xpEarned: 0)
    }

    private func end(of trips: [Trip]) -> Date { trips.last!.endDate! }

    /// Краснодар → Владикавказ (ночь) → Тбилиси (три ночи, две поездки по
    /// городу) → обратно домой.
    private var georgia: [Trip] {[
        trip(day: 0, hour: 9, from: krd, to: vld, km: 480, hours: 5.2),
        trip(day: 1, hour: 9, from: vld, to: tbs, km: 210, hours: 4.8),
        trip(day: 2, hour: 11, from: tbs, to: CLLocationCoordinate2D(latitude: 41.75, longitude: 44.80), km: 8, hours: 0.4),
        trip(day: 3, hour: 12, from: tbs, to: CLLocationCoordinate2D(latitude: 41.84, longitude: 44.72), km: 22, hours: 0.7),
        trip(day: 4, hour: 9, from: tbs, to: vld, km: 210, hours: 4.7),
        trip(day: 5, hour: 9, from: vld, to: krd, km: 480, hours: 5.2),
    ]}

    /// Коммьют 80 км туда-обратно каждый день, 14 дней подряд.
    private var commute: [Trip] {
        (0..<14).flatMap { day in
            [trip(day: day, hour: 8, from: krd, to: work, km: 80, hours: 1.2),
             trip(day: day, hour: 18, from: work, to: krd, km: 80, hours: 1.3)]
        }
    }

    // MARK: - Дом

    func testInferHomePicksTheCellWithTheMostNights() {
        // 14 вечеров дома против трёх на даче — дом там, где ночей больше.
        var trips = commute
        for day in [1, 2, 3] {
            trips.append(trip(day: day, hour: 20, from: krd, to: dacha, km: 100, hours: 1.5))
            trips.append(trip(day: day + 1, hour: 7, from: dacha, to: krd, km: 100, hours: 1.5))
        }
        let home = JourneySuggester.inferHome(trips: trips)
        XCTAssertNotNil(home)
        XCTAssertEqual(home?.latitude ?? 0, krd.latitude, accuracy: 0.002)
        XCTAssertEqual(home?.longitude ?? 0, krd.longitude, accuracy: 0.002)
    }

    func testInferHomeStaysSilentOnThinData() {
        // Пять дней данных — вывод дома был бы гаданием, и один неверный
        // ответ отравил бы все подсказки разом.
        let thin = (0..<5).map { trip(day: $0, hour: 18, from: work, to: krd, km: 80, hours: 1.3) }
        XCTAssertNil(JourneySuggester.inferHome(trips: thin))
    }

    // MARK: - Что подсказывается

    func testWholeGeorgiaChainIsSuggested() {
        let trips = georgia
        let s = JourneySuggester.suggestion(trips: trips, home: krd, existing: [],
                                            now: end(of: trips).addingTimeInterval(3_600))
        XCTAssertEqual(s?.count, 6, "цепочка целиком, вместе с поездками по Тбилиси")
        XCTAssertEqual(s?.map(\.id), trips.map(\.id))
    }

    func testSuggestionWaitsForTheWayBack() {
        // Человек ещё в Тбилиси: путешествие не кончилось, предлагать нечего.
        let trips = Array(georgia.prefix(4))
        let s = JourneySuggester.suggestion(trips: trips, home: krd, existing: [],
                                            now: end(of: trips).addingTimeInterval(3_600))
        XCTAssertNil(s)
    }

    // MARK: - Что НЕ подсказывается

    func testDailyCommuteIsNotAJourney() {
        // 80 км от дома каждый день, но ночь всегда дома.
        let trips = commute
        let s = JourneySuggester.suggestion(trips: trips, home: krd, existing: [],
                                            now: end(of: trips).addingTimeInterval(3_600))
        XCTAssertNil(s)
    }

    func testSameDayOutAndBackIsNotAJourney() {
        // Джубга: 200 км к морю и назад в тот же день — не путешествие.
        let trips = [trip(day: 0, hour: 7, from: krd, to: dzhubga, km: 200, hours: 3),
                     trip(day: 0, hour: 18, from: dzhubga, to: krd, km: 200, hours: 3.2)]
        let s = JourneySuggester.suggestion(trips: trips, home: krd, existing: [],
                                            now: end(of: trips).addingTimeInterval(3_600))
        XCTAssertNil(s)
    }

    func testWeekendsAtTheDachaAreUsualEnvironment() {
        // Ночь на даче — ночь не дома по геометрии, но место, куда приезжают
        // каждые выходные, обычная среда, а не путешествие.
        var trips: [Trip] = []
        for week in 0..<4 {
            trips.append(trip(day: week * 7, hour: 10, from: krd, to: dacha, km: 100, hours: 1.5))
            trips.append(trip(day: week * 7 + 1, hour: 17, from: dacha, to: krd, km: 100, hours: 1.5))
        }
        let s = JourneySuggester.suggestion(trips: trips, home: krd, existing: [],
                                            now: end(of: trips).addingTimeInterval(3_600))
        XCTAssertNil(s)
    }

    func testTripAlreadyInAJourneyBreaksTheChain() {
        let trips = georgia
        let taken = Journey(startDate: trips[1].startDate.addingTimeInterval(-60),
                            endDate: trips[1].startDate.addingTimeInterval(60))
        let s = JourneySuggester.suggestion(trips: trips, home: krd, existing: [taken],
                                            now: end(of: trips).addingTimeInterval(3_600))
        XCTAssertNil(s, "поездка уже в путешествии — цепочка через неё не идёт")
    }

    func testOldChainIsNotOfferedForever() {
        // Вернулись месяц назад: подсказка «Похоже на путешествие» уместна
        // по горячим следам, а не при каждом входе в «Мои» до конца времён.
        let trips = georgia
        let s = JourneySuggester.suggestion(trips: trips, home: krd, existing: [],
                                            now: end(of: trips).addingTimeInterval(30 * 86_400))
        XCTAssertNil(s)
    }
}
