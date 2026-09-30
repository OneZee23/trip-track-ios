import XCTest
@testable import TripTrack

/// Немецкий на 13 mini: зазор ровно НОЛЬ, и первый же перенос включает
/// прокрутку. Подвал при этом обязан остаться закреплённым — иначе цена и
/// условия уедут вместе с содержимым, а это отказ ревью Apple.
final class ProPaywallOverflowTests: XCTestCase {

    /// 13 mini — самый тесный телефон набора: зазора над подвалом у него нет
    /// вовсе. Матрица обещает «8», но её подвал записан как 184 при
    /// собственной сумме частей 192 (см. `ProLayout`), и следствие этой
    /// разницы — ровно здесь.
    func testFooterStaysPinnedWhenTheSetOverflows() {
        let mini = ProLayout(height: 812, safeTop: 50, safeBottom: 34)
        XCTAssertEqual(mini.roomAboveFooter - ProLayout.contentAboveFooter, 0,
                       "у 13 mini запаса нет — это и есть «впритык»")
        XCTAssertFalse(mini.paywallScrolls, "впритык — это ещё НЕ прокрутка")

        // Один перенос заголовка строки набора — плюс 18 точек.
        let overflowed = ProLayout.contentAboveFooter + 18
        XCTAssertGreaterThan(overflowed, mini.roomAboveFooter, "включается прокрутка")
        XCTAssertEqual(mini.footer, 226, "подвал не меняется от переполнения")
    }

    /// Подвал закреплён на ВСЕХ телефонах и не зависит ни от содержимого, ни
    /// от того, прокручивается ли верх. Цена, период и условия обязаны быть
    /// видны до покупки без прокрутки — это требование Apple, не вкус.
    func testTheFooterIsTheSameHeightWhereverTheContentFits() {
        let phones: [(String, ProLayout)] = [
            ("SE", ProLayout(height: 667, safeTop: 20, safeBottom: 0)),
            ("13 mini", ProLayout(height: 812, safeTop: 50, safeBottom: 34)),
            ("13/14", ProLayout(height: 844, safeTop: 47, safeBottom: 34)),
            ("15/16", ProLayout(height: 852, safeTop: 59, safeBottom: 34)),
            ("Pro Max", ProLayout(height: 932, safeTop: 62, safeBottom: 34)),
        ]
        for (name, layout) in phones {
            let expected = ProLayout.footerParts + (layout.safeBottom > 0 ? layout.safeBottom : 4)
            XCTAssertEqual(layout.footer, expected, name)
        }
    }

    /// Прокрутка включается ровно там, где содержимое не влезло, и нигде
    /// больше: лишний жест на телефоне, где всё видно, — это отскок на пустом
    /// месте.
    func testScrollingTurnsOnExactlyWhereItIsNeeded() {
        XCTAssertTrue(ProLayout(height: 667, safeTop: 20, safeBottom: 0).paywallScrolls,
                      "у SE содержимое не влезает")
        XCTAssertFalse(ProLayout(height: 844, safeTop: 47, safeBottom: 34).paywallScrolls)
        XCTAssertFalse(ProLayout(height: 932, safeTop: 62, safeBottom: 34).paywallScrolls)
    }

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
