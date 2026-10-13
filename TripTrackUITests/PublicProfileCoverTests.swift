import XCTest

/// Someone's paid profile background is visible on their profile as a card,
/// not as a torn strip (0.8.9, owner's choice 11 Oct 2026).
///
/// Before, the background was a ~60 pt band behind the top half of the avatar
/// and the cream page showed right under it. Checked on the frame: the band
/// UNDER the avatar — where the old strip had already ended — must be the
/// dark cover, not the page.
final class PublicProfileCoverTests: XCTestCase {
    func testPremiumBackgroundFillsTheHeroCard() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-debug-foreign-trip",
                                "-debug-foreign-profile", "pro", "-appLanguage", "ru", "-appThemeMode", "light"]
        app.launch()
        let preview = app.staticTexts["Foreign trip preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 25))
        preview.tap()
        let pill = app.buttons["detail_author_pill"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        pill.tap()
        let name = app.staticTexts["profile_display_name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        sleep(1)

        let screenshot = app.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = "public_profile_cover"
        shot.lifetime = .keepAlways
        add(shot)

        // Below the name row, left of centre: inside the hero card, outside
        // the old strip. Light theme page is #F8F6F2 (luma ≈ 0.97).
        let probe = CGRect(x: 30, y: name.frame.maxY + 40, width: 60, height: 12)
        let luma = Self.meanLuma(screenshot, rect: probe, windowWidth: app.windows.firstMatch.frame.width)
        XCTAssertLessThan(luma, 0.5, "The profile background must fill the hero card (luma \(luma))")
    }

    private static func meanLuma(_ screenshot: XCUIScreenshot, rect: CGRect, windowWidth: CGFloat) -> Double {
        guard let image = screenshot.image.cgImage else { return 1 }
        let scale = CGFloat(image.width) / windowWidth
        guard let crop = image.cropping(to: CGRect(x: rect.minX * scale, y: rect.minY * scale,
                                                   width: rect.width * scale, height: rect.height * scale)) else { return 1 }
        var data = [UInt8](repeating: 0, count: 4)
        data.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.interpolationQuality = .medium
            context?.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return (0.2126 * Double(data[0]) + 0.7152 * Double(data[1]) + 0.0722 * Double(data[2])) / 255
    }
}
