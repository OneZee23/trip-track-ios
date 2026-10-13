import XCTest

/// Низ чужой карты (12 окт 2026). Владелец на устройстве: «снизу криво всё
/// выглядит». Лист сводки был своим, белым, со своими колонками и ручкой,
/// которая ничего не тянет, — и кончался над полоской «Домой», так что под
/// ним снова проступала карта. И у французского водителя с 1 842 км стояло
/// «0 регионов»: атлас делит на регионы двадцать стран, а Францию — нет.
///
/// Офлайн-фикстура `-debug-foreign-trip`: чужая поездка в ленте → автор →
/// «Карта». `-debug-foreign-map france` (по умолчанию) — две длинные поездки
/// по Франции. С 13 окт атлас делит на регионы весь мир, Францию тоже, и путь
/// «ноль скрыт» эта фикстура больше не проходит: само правило держит
/// `PublicMapRegionsTileTests`, а здесь — что ноль не доехал до сводки.
final class PublicMapSummaryTests: XCTestCase {
    func testSummaryReachesTheBottomAndDoesNotInventZeroRegions() throws {
        try check(theme: "light")
    }

    func testSummaryReachesTheBottomInTheDarkTheme() throws {
        try check(theme: "dark")
    }

    private func check(theme: String) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-debug-foreign-trip",
                                "-debug-foreign-profile", "pro", "-appLanguage", "ru", "-appThemeMode", theme]
        app.launch()
        let preview = app.staticTexts["Foreign trip preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 25))
        preview.tap()
        let pill = app.buttons["detail_author_pill"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        pill.tap()
        XCTAssertTrue(app.staticTexts["profile_display_name"].firstMatch.waitForExistence(timeout: 10))

        let mapCard = app.staticTexts["Карта"].firstMatch
        for _ in 0..<6 where !(mapCard.exists && mapCard.isHittable) { app.swipeUp() }
        XCTAssertTrue(mapCard.waitForExistence(timeout: 5))
        mapCard.tap()

        let summary = app.otherElements["public_map_summary"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 20))
        // Числа приехали: два маршрута.
        XCTAssertTrue(app.staticTexts["2"].firstMatch.waitForExistence(timeout: 20))
        sleep(2)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "public_map_summary_\(theme)"
        shot.lifetime = .keepAlways
        add(shot)

        // Ни одного нуля в сводке: ноль при маршрутах — не число.
        XCTAssertFalse(summary.staticTexts["0"].exists,
                       "a zero is shown in another person's summary")

        // Под листом — его же цвет до физического низа, а не карта: самый
        // нижний ряд пикселей окна равен цвету листа над полоской «Домой».
        let window = app.windows.firstMatch.frame
        let image = app.screenshot()
        let sheetColor = Self.luma(image, at: CGPoint(x: 30, y: summary.frame.maxY - 6), width: window.width)
        let bottomColor = Self.luma(image, at: CGPoint(x: 30, y: window.maxY - 3), width: window.width)
        XCTAssertEqual(bottomColor, sheetColor, accuracy: 0.02,
                       "the summary sheet must run to the bottom edge (sheet \(sheetColor), edge \(bottomColor))")
    }

    private static func luma(_ shot: XCUIScreenshot, at point: CGPoint, width: CGFloat) -> Double {
        guard let image = shot.image.cgImage else { return -1 }
        let scale = CGFloat(image.width) / width
        let rect = CGRect(x: point.x * scale, y: point.y * scale, width: 4 * scale, height: 2 * scale).integral
        guard let crop = image.cropping(to: rect) else { return -1 }
        var data = [UInt8](repeating: 0, count: 4)
        data.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let r = 0.2126 * Double(data[0])
        let g = 0.7152 * Double(data[1])
        let b = 0.0722 * Double(data[2])
        return (r + g + b) / 255
    }
}
