import XCTest
@testable import TripTrack

/// Разовая карточка «профиль теперь показывает больше» (0.6.3).
///
/// 0.6.3 включает пер-блочную видимость с дефолтом «всё открыто». Это
/// осознанное решение владельца продукта, но у существующих аккаунтов наружу
/// поехало то, на что они не подписывались, — и единственное, что делает такой
/// дефолт честным, это сказать о нём вслух ровно один раз.
///
/// Тот же паттерн, что у `ProfileSyncLatch`: отсутствующая запись означает «не
/// показывали», а не «показывали». Ошибиться здесь можно только в одну
/// сторону — лишний показ раздражает, пропущенный оставляет человека в
/// неведении о том, что о нём стало видно.
final class VisibilityNoticeTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "visibility.notice.tests")!
        defaults.removePersistentDomain(forName: "visibility.notice.tests")
    }

    func testShowsToASignedInAccountThatHasNotSeenIt() {
        XCTAssertTrue(VisibilityNoticeLatch.needsShow(isSignedIn: true, isPublicProfile: true, defaults: defaults))
    }

    func testAbsentRecordMeansNotShownYet() {
        // Не «по умолчанию показано»: аккаунты, обновившиеся до появления
        // защёлки, — это ровно те, кому карточку и надо показать.
        defaults.removeObject(forKey: "com.triptrack.visibility.noticeShown")

        XCTAssertTrue(VisibilityNoticeLatch.needsShow(isSignedIn: true, isPublicProfile: true, defaults: defaults))
    }

    func testDoesNotShowTwice() {
        VisibilityNoticeLatch.markShown(defaults)

        XCTAssertFalse(VisibilityNoticeLatch.needsShow(isSignedIn: true, isPublicProfile: true, defaults: defaults))
    }

    func testDoesNotShowWhenThePublicProfileIsOff() {
        // Наружу ничего не поехало: «о вас стало видно больше» было бы
        // неправдой, и первой же неправдой про приватность.
        XCTAssertFalse(VisibilityNoticeLatch.needsShow(
            isSignedIn: true, isPublicProfile: false, defaults: defaults))
    }

    func testWaitsForTheServerAnswerInsteadOfGuessing() {
        XCTAssertFalse(VisibilityNoticeLatch.needsShow(
            isSignedIn: true, isPublicProfile: nil, defaults: defaults))
    }

    func testDoesNotShowToAGuest() {
        // Гостю нечего показывать: у него нет публичного профиля, и карточка
        // про «вас стало видно больше» была бы неправдой.
        XCTAssertFalse(VisibilityNoticeLatch.needsShow(isSignedIn: false, isPublicProfile: true, defaults: defaults))
    }

    func testResetOnSignOutSoTheNextAccountIsToldToo() {
        VisibilityNoticeLatch.markShown(defaults)
        VisibilityNoticeLatch.reset(defaults)

        XCTAssertTrue(
            VisibilityNoticeLatch.needsShow(isSignedIn: true, isPublicProfile: true, defaults: defaults),
            "следующий Apple ID на этом телефоне не должен наследовать чужую отметку «уже видел»"
        )
    }
}
