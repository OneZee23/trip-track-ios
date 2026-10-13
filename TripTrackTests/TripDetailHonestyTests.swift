import XCTest
import SwiftUI
import UIKit
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

    /// Цифры дистанции читаются на белой карточке: не ниже 3 : 1 (WCAG для
    /// крупного текста). В тёмной теме цвет прежний — там у него запас.
    func testDistanceDigitsClearContrastOnTheCard() {
        let light = AppTheme.colors(for: .light)
        let ratio = Self.contrast(UIColor(light.distance), UIColor(light.card))
        XCTAssertGreaterThanOrEqual(ratio, 3.0, "distance on a white card: \(ratio)")
        let dark = AppTheme.colors(for: .dark)
        XCTAssertEqual(UIColor(dark.distance), UIColor(AppTheme.green))
    }

    private static func contrast(_ a: UIColor, _ b: UIColor) -> Double {
        func luminance(_ c: UIColor) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0, al: CGFloat = 0
            c.getRed(&r, green: &g, blue: &bl, alpha: &al)
            func lin(_ v: CGFloat) -> Double {
                let v = Double(v); return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(bl)
        }
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
