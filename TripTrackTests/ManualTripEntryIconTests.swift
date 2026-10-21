import XCTest

/// «+» вместо замка у входа во вписанную поездку (0.9.1).
///
/// Владелец на устройстве 21 окт 2026: без подписки в шапке «Истории» стоял
/// замок, и было непонятно, что за ним. Нажатие и так открывает витрину PRO
/// (`ManualTripEntry` показывает её вместо листа), поэтому вход выглядит
/// одинаково для всех, а о подписке говорит витрина. Экраном это не
/// проверить без витрины с ценами, поэтому сторож читает исходник, как
/// `AtlasLocationSourceTests`.
final class ManualTripEntryIconTests: XCTestCase {

    func testManualTripEntriesNeverDrawALock() throws {
        let profile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TripTrack/Views/Profile/ProfileView.swift")
        let text = try String(contentsOf: profile, encoding: .utf8)

        XCTAssertFalse(text.contains("ManualTripEntry.isLocked ?"),
                       "вход во вписанную поездку снова рисует замок вместо «+»")
        XCTAssertTrue(text.contains("accessibilityIdentifier(\"profile_history_add\")"),
                      "кнопка «+» в шапке «Истории» пропала или переименована")
    }
}

/// Шеврон в «Зале славы» обещает, что строка открывается (0.9.1). На чужой
/// статистике обещание не держалось: стрелка рисовалась, кнопки не было —
/// владелец нажимал «Самая длинная» и «Лучший день», и ничего не
/// происходило. Сторож читает исходник: условие кнопки не имеет права снова
/// разойтись с условием шеврона.
final class StatsRecordRowTapTests: XCTestCase {

    func testEveryRowWithAChevronIsAButtonOnBothScreens() throws {
        let stats = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TripTrack/Views/Profile/StatsScreenView.swift")
        let text = try String(contentsOf: stats, encoding: .utf8)

        XCTAssertFalse(text.contains("if let tripId = row.tripId, !isRemote"),
                       "строка рекорда снова глухая на чужом экране, а шеврон рисуется")
        XCTAssertTrue(text.contains("openForeignTrip(tripId"),
                      "чужая поездка рекорда должна открываться")
    }
}

/// Вариант B статистики (0.9.1): красное на экране — только итог и
/// столбики. Мелкий акцент на тёмной карточке даёт 3.3 : 1 и не проходит
/// 4.5 : 1 для текста, поэтому выбранный месяц, выбранная кнопка, числа
/// рекордов и подпись «год назад» идут чернилами. Сторож читает исходник: экранный цвет мелкой
/// подписи тестом не задать без кадра.
final class StatsAccentDisciplineTests: XCTestCase {

    func testSmallTextOnTheStatsScreenIsNeverAccent() throws {
        let stats = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TripTrack/Views/Profile/StatsScreenView.swift")
        let text = try String(contentsOf: stats, encoding: .utf8)

        XCTAssertFalse(text.contains("foregroundStyle(isOn ? AppTheme.accent"),
                       "выбранная кнопка периода снова красная мелким текстом")
        XCTAssertFalse(text.contains("foregroundStyle(selected ? AppTheme.accent"),
                       "подпись выбранного месяца снова красная")
        XCTAssertTrue(text.contains("Text(distance).foregroundColor(AppTheme.accent)"),
                      "крупный итог потерял свой единственный красный")
        // Красный текст на экране ровно один — итог. Остальные
        // `AppTheme.accent` — столбики, кнопка пустого экрана и «Повторить».
        let accentText = text.components(separatedBy: "foregroundStyle(AppTheme.accent)").count - 1
        XCTAssertLessThanOrEqual(accentText, 3,
                                 "появился новый мелкий красный текст — проверь его контраст на тёмной теме")
    }
}
