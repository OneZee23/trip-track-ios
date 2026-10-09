import XCTest
@testable import TripTrack

/// Copy budgets keep the storefront concise in all supported languages.
/// Reachability with real text and a pinned offer is covered by UI tests.
final class ProPaywallOverflowTests: XCTestCase {

    /// Серая строка набора не длиннее 32 знаков ни на одном языке — иначе
    /// строка 52 растёт переносом, и набор уходит за подвал раньше срока.
    ///
    /// Порог НЕ поднимался под перевод: семь строк на пяти языках укорочены
    /// (немецкие «8 Hintergründe über die kostenlosen hinaus» → «8
    /// zusätzliche Hintergründe» и «Die Strecke, die nicht aufgezeichnet
    /// wurde» → «Die nicht erfasste Strecke», плюс en, fr, it, tr). Поднять
    /// порог значило бы починить сторожа вместо того, что он сторожит.
    func testFeatureSubtitlesStayShortInEveryLanguage() {
        for lang in LanguageManager.Language.allCases {
            for feature in PlusFeature.allCases {
                let text = feature.proSubtitle(lang)
                XCTAssertLessThanOrEqual(
                    text.count, 32,
                    "\(lang.rawValue)/\(feature): «\(text)» — \(text.count) знаков")
            }
        }
    }

    /// И заголовок строки тоже: он крупнее подписи, и перенос у него дороже.
    func testFeatureTitlesStayShortInEveryLanguage() {
        for lang in LanguageManager.Language.allCases {
            for feature in PlusFeature.allCases {
                let text = feature.proTitle(lang)
                XCTAssertLessThanOrEqual(
                    text.count, 28,
                    "\(lang.rawValue)/\(feature): «\(text)» — \(text.count) знаков")
            }
        }
    }
}
