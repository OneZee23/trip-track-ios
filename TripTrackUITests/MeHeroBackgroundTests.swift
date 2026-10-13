import XCTest

/// The «Me» card is light unless a profile background is chosen (13 Oct 2026).
///
/// Owner, on 0.9.0 (79): the dark default made «Me» look like it already had
/// a cover, while «Фон профиля» said «Обычный» — the setting looked like it did
/// nothing. Measured by pixels, not by eye. Light theme: the default must be
/// light and a chosen background must darken the same card. Dark theme: every
/// card is dark there, so the check is the warm accent tint, which neither a
/// background nor the dark ink card of 0.9.0 (79) has.
@MainActor
final class MeHeroBackgroundTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private struct Tone { let light, red, blue: Double }

    private func heroTone(theme: String, background: String) throws -> Tone {
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-seed-map-demo",
                                "-appLanguage", "ru", "-appThemeMode", theme,
                                "-com.triptrack.settings.profileBackground", background]
        app.launch()
        defer { app.terminate() }
        let tab = app.buttons["tab_profile"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 40))
        tab.tap()
        let strip = app.buttons["profile_stats_strip"].firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 15))
        sleep(1)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "me_hero_\(theme)_\(background.isEmpty ? "default" : background)"
        attachment.lifetime = .keepAlways
        add(attachment)

        // A band across the card between the avatar row and the stats line,
        // left of the text: background, not glyphs.
        let avatar = app.buttons["profile_avatar"].firstMatch.frame
        let scale = shot.image.scale
        let band = CGRect(x: avatar.minX * scale, y: (avatar.maxY + 6) * scale,
                          width: 12 * scale, height: max(4, (strip.frame.minY - avatar.maxY - 12)) * scale)
        guard let cg = shot.image.cgImage?.cropping(to: band) else {
            XCTFail("No pixels for the card band"); return Tone(light: 0, red: 0, blue: 0)
        }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var light = 0.0, red = 0.0, blue = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            light += 0.2126 * r + 0.7152 * g + 0.0722 * b
            red += r
            blue += b
        }
        let n = Double(w * h)
        return Tone(light: light / n, red: red / n, blue: blue / n)
    }

    func testDefaultCardIsLightAndAChosenBackgroundDarkensIt() throws {
        let plain = try heroTone(theme: "light", background: "")
        let chosen = try heroTone(theme: "light", background: "ocean")
        print("PROBE hero light: default=\(plain) ocean=\(chosen)")
        XCTAssertGreaterThan(plain.light, 0.8, "Without a chosen background the card must be light")
        XCTAssertLessThan(chosen.light, plain.light - 0.3, "A chosen background must darken the card")
    }

    func testDarkThemeDefaultCarriesTheWarmTintNotACover() throws {
        let plain = try heroTone(theme: "dark", background: "")
        let chosen = try heroTone(theme: "dark", background: "ocean")
        print("PROBE hero dark: default=\(plain) ocean=\(chosen)")
        XCTAssertGreaterThan(plain.red - plain.blue, 0.02,
                             "The default dark card carries the warm accent tint")
        XCTAssertGreaterThan(chosen.blue - chosen.red, 0.02,
                             "A chosen background shows its own artwork")
    }
}
