import XCTest
@testable import TripTrack

/// Окно правки путешествия: чем открывается лист и что показывают пикеры.
///
/// Повод — вылет. У владельца лежало путешествие «На море бархатный сезон» с
/// окном 15–30 сентября, заведённое, когда будущее ещё не запрещалось. Пикеры
/// строили диапазон `startDate...Date()`, у которого 15-е больше 10-го, и
/// Swift падал прямо на построении: «Fatal error: Range requires lowerBound <=
/// upperBound». Правка дат умирала в момент нажатия «Изменить».
///
/// Половина тестов здесь — про то, что нормальные даты НЕ шевелятся: зажим,
/// который двигает прошедшее окно, чинил бы вылет ценой чужой истории.
final class JourneyEditWindowTests: XCTestCase {
    /// Полдень по местному: «сейчас» посреди суток, чтобы «тот же день» и
    /// «раньше/позже» не сходились в одну точку на границе полуночи.
    private let now = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))
        .addingTimeInterval(12 * 3_600)

    private func day(_ offset: Double, hour: Double = 0) -> Date {
        now.addingTimeInterval(offset * 86_400 + hour * 3_600)
    }

    // MARK: - Зажим при открытии

    func testFutureWindowClampsToNow() {
        // То самое «15–30 сентября» при «сегодня 10-е».
        let w = JourneyEditSheet.clampedWindow(start: day(5), end: day(20), now: now)
        XCTAssertEqual(w.start, now, "будущее начало зажимается к сейчас")
        XCTAssertEqual(w.end, now, "будущий конец тоже: путешествие — это то, что уже проехали")
    }

    func testFutureEndAloneClampsAndKeepsPastStart() {
        let start = day(-6)
        let w = JourneyEditSheet.clampedWindow(start: start, end: day(4), now: now)
        XCTAssertEqual(w.start, start, "прошедшее начало трогать не за что")
        XCTAssertEqual(w.end, now)
    }

    func testInvertedPairIsSwapped() {
        let earlier = day(-9)
        let later = day(-2)
        let w = JourneyEditSheet.clampedWindow(start: later, end: earlier, now: now)
        XCTAssertEqual(w.start, earlier, "меньшая дата — начало")
        XCTAssertEqual(w.end, later, "большая — конец")
    }

    /// Открытое окно (`end == nil`) закрывается СЕГОДНЯ, а не собственным
    /// началом. По `Journey.contains` оно тянется вперёд до конца времён, и
    /// свернуть его в одни сутки значило бы выбросить все плечи, кроме
    /// первого дня, — при сохранении одного лишь ИМЕНИ. Такая запись приезжает
    /// пулом со второго телефона: `endDate` optional и в схеме, и в проводе.
    func testOpenWindowClosesAtToday() {
        let start = day(-3)
        let w = JourneyEditSheet.clampedWindow(start: start, end: nil, now: now)
        XCTAssertEqual(w.start, start, "начало не трогаем")
        XCTAssertEqual(w.end, now, "конец — сегодня: поездок из будущего не бывает")
    }

    func testOpenWindowInFutureCollapsesToToday() {
        // Будущее начало зажимается, а `now` в роли конца зажимать не за что:
        // обе границы сходятся в сегодняшний день.
        let w = JourneyEditSheet.clampedWindow(start: day(7), end: nil, now: now)
        XCTAssertEqual(w.start, now)
        XCTAssertEqual(w.end, now)
    }

    func testPastWindowIsUntouchedToTheSecond() {
        let start = day(-30, hour: 7)
        let end = day(-24, hour: 21)
        let w = JourneyEditSheet.clampedWindow(start: start, end: end, now: now)
        XCTAssertEqual(w.start.timeIntervalSince1970, start.timeIntervalSince1970, accuracy: 0)
        XCTAssertEqual(w.end.timeIntervalSince1970, end.timeIntervalSince1970, accuracy: 0)
    }

    func testTodaysEveningEndIsKept() {
        // Конец сегодняшнего дня в базе лежит как 23:59:59. Это не будущее:
        // пикер выбирает ДНИ, и подрезать его до текущих 12:00 значит менять
        // хранимое значение там, где человек не увидит разницы.
        let end = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400 - 1)
        let w = JourneyEditSheet.clampedWindow(start: day(-2), end: end, now: now)
        XCTAssertEqual(w.end, end)
    }

    // MARK: - Диапазоны, которые невозможно перевернуть

    func testRangesAreValidAndContainSelectionForAnyPair() {
        let offsets: [Double] = [-40, -1, 0, 1, 40]
        for s in offsets {
            for e in offsets {
                let start = day(s)
                let end = day(e)
                let sr = JourneyEditSheet.startBounds(start: start, end: end, now: now)
                let er = JourneyEditSheet.endBounds(start: start, end: end, now: now)
                // Само построение уже упало бы, будь границы переставлены;
                // проверка оставлена явной, чтобы падение было читаемым.
                XCTAssertLessThanOrEqual(sr.lowerBound, sr.upperBound, "start \(s), end \(e)")
                XCTAssertLessThanOrEqual(er.lowerBound, er.upperBound, "start \(s), end \(e)")
                XCTAssertTrue(sr.contains(start), "выбор вне своего диапазона: start \(s), end \(e)")
                XCTAssertTrue(er.contains(end), "выбор вне своего диапазона: start \(s), end \(e)")
            }
        }
    }

    func testRangesDoNotOpenTheFutureBeyondTheCurrentValue() {
        let past = day(-5)
        XCTAssertEqual(JourneyEditSheet.startBounds(start: past, end: day(30), now: now).upperBound, now,
                       "будущий конец не поднимает потолок начала выше сегодняшнего дня")
        XCTAssertEqual(JourneyEditSheet.endBounds(start: past, end: past, now: now).upperBound, now,
                       "потолок конца — сейчас, дальше только за уже выбранным значением")
    }

    func testStartCeilingIsTheEndDateWhileBothAreInThePast() {
        let start = day(-9)
        let end = day(-4)
        XCTAssertEqual(JourneyEditSheet.startBounds(start: start, end: end, now: now).upperBound, end,
                       "начало по-прежнему не заезжает за конец")
    }

    // MARK: - Двигал ли даты ЧЕЛОВЕК

    func testDatesUntouchedWhenNothingWasPicked() {
        let opened = (start: day(-6), end: day(-2))
        XCTAssertFalse(JourneyEditSheet.datesMoved(start: opened.start, end: opened.end, opened: opened))
    }

    /// Пикер отдаёт свой час, а в базе лежат утро и вечер тех же суток. День
    /// тот же — значит границу человек не двигал, и «Сохранить» не имеет права
    /// гаснуть. Часы у `day()` отсчитываются от полудня, поэтому 07:00 это
    /// `hour: -5`, а 21:00 — `hour: 9`.
    func testDatesUntouchedWhenOnlyTheTimeOfDayDiffers() {
        let opened = (start: day(-6, hour: -5), end: day(-2, hour: 9))
        XCTAssertFalse(JourneyEditSheet.datesMoved(start: day(-6), end: day(-2), opened: opened))
    }

    func testEachBoundaryIsNoticedSeparately() {
        let opened = (start: day(-6), end: day(-2))
        XCTAssertTrue(JourneyEditSheet.datesMoved(start: day(-7), end: opened.end, opened: opened),
                      "уехало начало")
        XCTAssertTrue(JourneyEditSheet.datesMoved(start: opened.start, end: day(-1), opened: opened),
                      "уехал конец")
    }

    func testSwappedPickersAreNotAMove() {
        // Перепутанные местами границы — описка, а не правка: окно
        // разворачивается само, ровно как в `plannedWindow()`.
        let opened = (start: day(-6), end: day(-2))
        XCTAssertFalse(JourneyEditSheet.datesMoved(start: opened.end, end: opened.start, opened: opened))
    }

    /// Тот самый узкий случай. Признак «даты трогали» раньше сравнивал пикеры
    /// с ХРАНИМОЙ записью, а её границы к тому моменту уже подвинул
    /// `clampedWindow` в `init`. У окна с будущими датами (и у окна с
    /// `endDate == nil`) он оказывался истинным ещё до того, как человек
    /// коснулся экрана, — и такая запись БЕЗ плеч не переименовывалась вовсе:
    /// «Сохранить» гасло, оставляя единственное действие «Удалить».
    func testClampAtOpeningIsNotAMoveByTheUser() {
        let storedStart = day(5)          // «15–30 сентября» при «сегодня» 10-м
        let storedEnd = day(20)
        let opened = JourneyEditSheet.clampedWindow(start: storedStart, end: storedEnd, now: now)

        XCTAssertFalse(JourneyEditSheet.datesMoved(start: opened.start, end: opened.end, opened: opened),
                       "лист открылся — человек ещё ничего не трогал")
        XCTAssertTrue(!Calendar.current.isDate(opened.start, inSameDayAs: storedStart),
                      "зажим и правда подвинул границу — иначе тест ничего не проверяет")
    }

    func testOpenWindowClampIsNotAMoveByTheUser() {
        let opened = JourneyEditSheet.clampedWindow(start: day(-10), end: nil, now: now)
        XCTAssertFalse(JourneyEditSheet.datesMoved(start: opened.start, end: opened.end, opened: opened))
    }
}
