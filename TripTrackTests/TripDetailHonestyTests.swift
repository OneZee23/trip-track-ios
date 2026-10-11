import XCTest
@testable import TripTrack

/// The trip screen says only what the app measured (review 11 Oct 2026).
final class TripDetailHonestyTests: XCTestCase {
    /// «Сохранённая копия обсуждения» only when the copy exists. A trip that
    /// has never been on the server has no copy, and sync is off by default —
    /// so the old line told nearly every owner their trip «is no longer on the
    /// server».
    func testReadOnlyDiscussionLineSaysArchiveOnlyWhenThereIsOne() {
        for lang in LanguageManager.Language.allCases {
            XCTAssertEqual(TripCommentsSection.readOnlyLine(isArchived: true, language: lang),
                           AppStrings.discussionArchived(lang))
            XCTAssertEqual(TripCommentsSection.readOnlyLine(isArchived: false, language: lang),
                           AppStrings.discussionNeedsCloud(lang))
            XCTAssertNotEqual(AppStrings.discussionNeedsCloud(lang), AppStrings.discussionArchived(lang),
                              "\(lang): the two cases must read differently")
        }
    }

    /// Same condition, same words: the companions row on this screen already
    /// says «поездка должна быть в облаке».
    func testNeedsCloudLineUsesTheCompanionsWording() {
        XCTAssertTrue(AppStrings.discussionNeedsCloud(.ru).contains("должна быть в облаке"))
        XCTAssertTrue(AppStrings.companionsPublishFirstHint(.ru).contains("должна быть в облаке"))
    }

    /// The bar starts transparent, becomes a toolbar once the map has
    /// scrolled away, and moves in 1/20 steps so a scroll does not re-render
    /// the map's body per point.
    func testHeroProgressThresholds() {
        let poster: CGFloat = 383, safe: CGFloat = 59
        XCTAssertEqual(TripDetailView.heroProgress(minY: 0, posterHeight: poster, safeAreaTop: safe), 0)
        XCTAssertEqual(TripDetailView.heroProgress(minY: 40, posterHeight: poster, safeAreaTop: safe), 0,
                       "over-scroll down keeps the bar transparent")
        XCTAssertEqual(TripDetailView.heroProgress(minY: -10_000, posterHeight: poster, safeAreaTop: safe), 1)
        let mid = TripDetailView.heroProgress(minY: -136, posterHeight: poster, safeAreaTop: safe)
        XCTAssertEqual(mid, 0.5, accuracy: 0.001)
        XCTAssertEqual((mid * 20).rounded(), mid * 20, "quantized to 1/20")
    }
}
