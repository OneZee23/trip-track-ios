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

    /// Неделя в одном отеле: каждый вечер машина возвращается в один и тот же
    /// двор. По общему счёту «обычной среды» этих вечеров хватало, чтобы отель
    /// стал местом, куда человек «всегда ездит», — и поездка отменяла сама
    /// себя. Свои ночи цепочка не считает.
    func testSameHotelEveryNightIsStillAJourney() {
        // 300 км строго на север: и «не дома», и дальше `awayRadius`.
        let hotel = CLLocationCoordinate2D(latitude: 47.73, longitude: 38.98)
        // Двор в двух километрах — оттуда машина возвращается в отель.
        let nearby = CLLocationCoordinate2D(latitude: 47.75, longitude: 38.98)
        var trips = [trip(day: 0, hour: 9, from: krd, to: hotel, km: 300, hours: 4)]
        for day in 1...4 {
            trips.append(trip(day: day, hour: 19, from: nearby, to: hotel, km: 12, hours: 1))
        }
        trips.append(trip(day: 5, hour: 9, from: hotel, to: krd, km: 300, hours: 4))

        let s = JourneySuggester.suggestion(trips: trips, home: krd, existing: [],
                                            now: end(of: trips).addingTimeInterval(3_600))

        XCTAssertEqual(s?.map(\.id), trips.map(\.id),
                       "цепочка целиком: четыре ночи в одном отеле не делают отель домом")
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

    func testNightTenKilometresFromHomeIsNotAJourney() {
        // Ночь у друга через город: место незнакомое (в кэше оно один раз), но
        // 10 км от дома — это не «уехал», а «заночевал не у себя». Порог
        // именно 50 км: иначе подсказка вылезала бы после каждой такой ночи.
        let near = CLLocationCoordinate2D(latitude: 45.12, longitude: 38.98)
        let trips = [trip(day: 0, hour: 22, from: krd, to: near, km: 10, hours: 0.3),
                     trip(day: 1, hour: 10, from: near, to: krd, km: 10, hours: 0.3)]
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

    // MARK: - Спрашивать ли про дом

    /// «Нет» — это на месяц, а не навсегда.
    ///
    /// Правило стояло тремя `if` внутри экрана и звучало «спросили — больше не
    /// спрашиваем», из-за чего человек, ответивший «нет» на третьей неделе
    /// записи (когда вывод показывал работу вместо двора), терял подсказки
    /// насовсем — задать дом руками в 0.6.6 нечем.
    func testHomeQuestionComesBackAMonthAfterNo() {
        let now = Date()
        let declined = now.addingTimeInterval(-JourneySuggester.homeReaskDelay - 60)
        XCTAssertTrue(JourneySuggester.shouldAskHome(homeLocation: nil, homeAsked: false,
                                                     declinedAt: declined, now: now))
    }

    func testHomeQuestionStaysAwayRightAfterNo() {
        let now = Date()
        XCTAssertFalse(JourneySuggester.shouldAskHome(
            homeLocation: nil, homeAsked: false,
            declinedAt: now.addingTimeInterval(-2 * 86_400), now: now))
    }

    func testHomeQuestionNeverComesBackAfterYes() {
        let now = Date()
        // «Да» закрывает вопрос навсегда, даже если дом потом стёрли: человек
        // уже ответил, и переспрашивать — навязчиво.
        XCTAssertFalse(JourneySuggester.shouldAskHome(homeLocation: nil, homeAsked: true,
                                                      declinedAt: nil, now: now))
        XCTAssertFalse(JourneySuggester.shouldAskHome(homeLocation: krd, homeAsked: true,
                                                      declinedAt: nil, now: now))
    }

    func testHomeQuestionIsAskedWhenNobodyAnsweredYet() {
        XCTAssertTrue(JourneySuggester.shouldAskHome(homeLocation: nil, homeAsked: false,
                                                     declinedAt: nil, now: Date()))
    }

    func testHomeQuestionIsSilentWhenHomeIsAlreadyKnown() {
        XCTAssertFalse(JourneySuggester.shouldAskHome(homeLocation: krd, homeAsked: false,
                                                      declinedAt: nil, now: Date()))
    }

    func testOldChainIsNotOfferedForever() {
        // Вернулись месяц назад: подсказка «Похоже на путешествие» уместна
        // по горячим следам, а не при каждом входе в «Мои» до конца времён.
        let trips = georgia
        let s = JourneySuggester.suggestion(trips: trips, home: krd, existing: [],
                                            now: end(of: trips).addingTimeInterval(30 * 86_400))
        XCTAssertNil(s)
    }

    // MARK: - Цепочка вокруг опорной (лист сборки)

    /// Геленджик и Дивноморское — та самая дорога 6 сентября, с которой
    /// владелец и открыл лист сборки.
    private let gelendzhik = CLLocationCoordinate2D(latitude: 44.56, longitude: 38.08)
    private let divnomorskoye = CLLocationCoordinate2D(latitude: 44.50, longitude: 38.13)
    /// 60 км строго на север от дома: город, но НЕ тот же город.
    private let otherTown = CLLocationCoordinate2D(latitude: 45.57, longitude: 38.98)

    /// Автозавершение разрезало дорогу домой пополам, и обе половины —
    /// одно путешествие: конец первой и начало второй совпадают.
    func testChainJoinsTwoLegsOfTheSameDay() {
        let leg1 = trip(day: 0, hour: 10, from: krd, to: gelendzhik, km: 177, hours: 2.5)
        let leg2 = trip(day: 0, hour: 15, from: gelendzhik, to: divnomorskoye, km: 9.6, hours: 0.23)

        let chain = JourneySuggester.chainAround(leg2, in: [leg1, leg2])

        XCTAssertEqual(chain.map(\.id), [leg1.id, leg2.id])
    }

    /// Поездка накануне по другому городу лежит в окне ±7 дней и потому
    /// попадает в лист — но галочки не получает: её конец в шестидесяти
    /// километрах от места, откуда началась дорога.
    func testChainSkipsAYesterdayTripSomewhereElse() {
        let city = trip(day: -1, hour: 18, from: otherTown, to: otherTown, km: 12, hours: 0.5)
        let leg1 = trip(day: 0, hour: 10, from: krd, to: gelendzhik, km: 177, hours: 2.5)
        let leg2 = trip(day: 0, hour: 15, from: gelendzhik, to: divnomorskoye, km: 9.6, hours: 0.23)

        let chain = JourneySuggester.chainAround(leg2, in: [city, leg1, leg2])

        XCTAssertEqual(chain.map(\.id), [leg1.id, leg2.id], "вчерашний город — не эта дорога")
    }

    /// Через три дня машина поехала ровно оттуда же, где встала. Место то же,
    /// история другая — рвёт её время, а не геометрия.
    func testChainBreaksOnALongGapAtTheSameSpot() {
        let leg1 = trip(day: 0, hour: 10, from: krd, to: gelendzhik, km: 177, hours: 2.5)
        let leg2 = trip(day: 0, hour: 15, from: gelendzhik, to: divnomorskoye, km: 9.6, hours: 0.23)
        let later = trip(day: 3, hour: 12, from: divnomorskoye, to: krd, km: 190, hours: 3)

        let chain = JourneySuggester.chainAround(leg2, in: [leg1, leg2, later])

        XCTAssertEqual(chain.map(\.id), [leg1.id, leg2.id])
    }

    /// Опорная поездка возвращается всегда, даже когда сцеплять не с чем:
    /// лист открывают, чтобы собрать путешествие, а не чтобы получить пустой
    /// список галочек.
    func testChainKeepsTheAnchorAlone() {
        let alone = trip(day: 0, hour: 10, from: krd, to: gelendzhik, km: 177, hours: 2.5)
        XCTAssertEqual(JourneySuggester.chainAround(alone, in: [alone]).map(\.id), [alone.id])
    }
}
