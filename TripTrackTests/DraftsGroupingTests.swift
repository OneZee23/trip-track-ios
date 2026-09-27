import XCTest
@testable import TripTrack

/// Группы списка черновиков и правило точки на вкладке «Я».
final class DraftsGroupingTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func trip(_ date: Date) -> Trip {
        Trip(id: UUID(), startDate: date, endDate: date.addingTimeInterval(600),
             distance: 1000, title: "t")
    }

    /// Порядок групп — «Сегодня», «Вчера», «Ранее», и внутри свежие сверху.
    func testGroupsComeInOrderAndFreshestFirst() {
        let now = Date()
        let earlier = now.addingTimeInterval(-6 * 86400)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let older = now.addingTimeInterval(-3600)

        let groups = DraftsGrouping.build(
            [trip(earlier), trip(older), trip(now), trip(yesterday)],
            now: now, calendar: calendar)

        XCTAssertEqual(groups.map(\.bucket), [.today, .yesterday, .earlier])
        XCTAssertEqual(groups[0].trips.count, 2)
        XCTAssertEqual(groups[0].trips[0].startDate, now, "свежая обязана стоять первой")
    }

    /// Пустая группа не рисуется: заголовок над пустотой ничего не называет.
    func testEmptyGroupsAreDropped() {
        let now = Date()
        let groups = DraftsGrouping.build([trip(now)], now: now, calendar: calendar)
        XCTAssertEqual(groups.map(\.bucket), [.today])
    }

    /// Граница дня — календарная, а не «минус сутки»: запись в 00:30 и
    /// «сейчас» в 23:00 того же дня это ОДИН день, хотя между ними 22 часа.
    func testDayBoundaryIsCalendarNotTwentyFourHours() {
        var c = calendar
        c.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let day = c.date(from: DateComponents(year: 2026, month: 9, day: 27))!
        let lateEvening = c.date(byAdding: .hour, value: 23, to: day)!
        let earlyMorning = c.date(byAdding: .minute, value: 30, to: day)!

        XCTAssertEqual(DraftsGrouping.bucket(for: earlyMorning, now: lateEvening, calendar: c),
                       .today)
        XCTAssertEqual(
            DraftsGrouping.bucket(for: c.date(byAdding: .hour, value: -2, to: day)!,
                                  now: lateEvening, calendar: c),
            .yesterday)
    }

    /// Точка на «Я»: горит, пока есть черновик СВЕЖЕЕ последнего открытия
    /// списка. Записанный ровно в ту же секунду не горит — его уже видели.
    func testTheDotBurnsOnlyForDraftsRecordedAfterTheListWasOpened() {
        let seen = Date()
        XCTAssertFalse(DraftsBadge.hasUnseen(drafts: [], seenAt: seen))
        XCTAssertFalse(DraftsBadge.hasUnseen(
            drafts: [trip(seen.addingTimeInterval(-60))], seenAt: seen))
        XCTAssertFalse(DraftsBadge.hasUnseen(drafts: [trip(seen)], seenAt: seen))
        XCTAssertTrue(DraftsBadge.hasUnseen(
            drafts: [trip(seen.addingTimeInterval(-60)), trip(seen.addingTimeInterval(1))],
            seenAt: seen))
        XCTAssertTrue(DraftsBadge.hasUnseen(drafts: [trip(seen)], seenAt: .distantPast),
                      "список не открывали ни разу — точка обязана гореть")
    }
}
