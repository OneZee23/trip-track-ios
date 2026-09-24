import XCTest
import UserNotifications
@testable import TripTrack

/// Только строители содержимого: `UNUserNotificationCenter.current()` в тестах
/// без хоста падает.
final class DraftNotificationTests: XCTestCase {
    func testStartNoticeIsPassive() {
        let content = NotificationManager.draftStartedContent(lang: .ru)
        XCTAssertEqual(content.interruptionLevel, .passive, "человек за рулём — ни звука, ни баннера")
        XCTAssertNil(content.sound)
    }

    func testConfirmPromptCarriesTheTripAndTheDistance() {
        let id = UUID()
        let content = NotificationManager.draftConfirmContent(tripId: id, metres: 7400, lang: .ru, unit: .km)
        XCTAssertEqual(content.categoryIdentifier, NotificationManager.tripDraftConfirmCategory)
        XCTAssertEqual(content.userInfo["tripId"] as? String, id.uuidString)
        XCTAssertTrue(content.body.contains("7.4"), "расстояние — через Measure, с точкой")
        XCTAssertFalse(content.body.contains("{distance}"))
    }

    /// Экран спрашивает «Твоя?» на переднем плане (`NotificationManager
    /// .presentationOptions`), уведомление — в кармане. Тот же контракт, что у
    /// `tripStartPromptCategory`.
    func testDraftConfirmPresentsSilentlyInForeground() {
        XCTAssertEqual(NotificationManager.presentationOptions(for: NotificationManager.tripDraftConfirmCategory), [])
    }
}
