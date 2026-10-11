import XCTest

/// The trip screen's top bar turns opaque once the map has scrolled away.
///
/// Until 0.8.9 it never did: the scroll offset reached the bar once, at 0, and
/// then never again, so the back and «…» circles floated over the trip's text
/// and the text ran under the clock. Every state of the bar looked right in
/// code, so the check is made on the FRAME: after scrolling, the band behind
/// the bar must be one flat colour (the bar), not the moments and tiles that
/// slide under a transparent one.
final class TripDetailTopBarScrollTests: XCTestCase {
    func testBarBecomesOpaqueAfterScrolling() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-seed-map-demo", "-seed-segment-demo",
                                "-appLanguage", "ru", "-appThemeMode", "light", "-selectedTabV2", "profile"]
        app.launch()
        XCTAssertTrue(app.buttons["tab_profile"].firstMatch.waitForExistence(timeout: 40))

        let field = app.textFields["profile_history_search"].firstMatch
        for _ in 0..<10 where !(field.exists && field.isHittable) { app.swipeUp() }
        field.tap()
        field.typeText("Ростов-на-Дону\n")
        let cell = app.historyTripCells.firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        for _ in 0..<4 where !cell.isHittable { app.swipeUp() }
        cell.tap()
        XCTAssertTrue(app.buttons["detail_map_expand"].firstMatch.waitForExistence(timeout: 10))

        let back = app.buttons["detail_back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        // Scroll until the «Моменты» timeline sits under the bar, so there is
        // always text behind it: on a transparent bar the band below can not
        // happen to land on flat background and pass by luck.
        let start = app.staticTexts["Старт"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch
        let target = back.frame.midY
        for _ in 0..<6 where start.frame.midY > target + 30 {
            let distance = min(start.frame.midY - target, window.frame.height * 0.6)
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            let to = from.withOffset(CGVector(dx: 0, dy: -distance))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.4)
        }

        let screenshot = app.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = "trip_bar_scrolled"
        shot.lifetime = .keepAlways
        add(shot)

        // Two bands a solid bar paints flat: the strip under the status bar,
        // and the gap between the back circle and the centred title. A
        // transparent bar shows the timeline sliding past in both.
        let width = window.frame.width
        let above = Self.lumaSpread(screenshot, band: CGRect(
            x: 16, y: back.frame.minY - 14, width: width - 32, height: 10), windowWidth: width)
        let gap = Self.lumaSpread(screenshot, band: CGRect(
            x: back.frame.maxX + 6, y: back.frame.minY + 4, width: 60, height: back.frame.height - 8),
            windowWidth: width)
        XCTAssertLessThan(max(above, gap), 0.04,
                          "Behind a scrolled bar there must be the bar, not the page (\(above), \(gap))")
    }

    private static func lumaSpread(_ screenshot: XCUIScreenshot, band: CGRect, windowWidth: CGFloat) -> Double {
        guard let image = screenshot.image.cgImage else { return 1 }
        let scale = CGFloat(image.width) / windowWidth
        let pixels = CGRect(x: band.minX * scale, y: band.minY * scale,
                            width: band.width * scale, height: band.height * scale)
        guard let crop = image.cropping(to: pixels) else { return 1 }
        let columns = 24, rows = 8
        var data = [UInt8](repeating: 0, count: columns * rows * 4)
        data.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: columns, height: rows,
                                    bitsPerComponent: 8, bytesPerRow: columns * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(crop, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        }
        var lumas: [Double] = []
        for i in stride(from: 0, to: data.count, by: 4) {
            lumas.append((0.2126 * Double(data[i]) + 0.7152 * Double(data[i + 1]) + 0.0722 * Double(data[i + 2])) / 255)
        }
        return (lumas.max() ?? 0) - (lumas.min() ?? 0)
    }
}
