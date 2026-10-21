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
