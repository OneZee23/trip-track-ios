import XCTest

/// Uses an offline API fixture, not a local trip: this is the actual foreign
/// trip path from Feed, including the delayed /social/trip refresh.
final class ForeignTripNavigationTests: XCTestCase {
    func testForeignTripLoadsUpdatesAndCanBeOpenedAgain() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-debug-foreign-trip"]
        app.launch()

        let preview = app.staticTexts["Foreign trip preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 15))

        for pass in 1...2 {
            preview.tap()
            let expand = app.buttons["detail_map_expand"].firstMatch
            XCTAssertTrue(expand.waitForExistence(timeout: 10), "Foreign trip must finish loading")
            XCTAssertTrue(app.staticTexts["Foreign trip updated"].firstMatch.waitForExistence(timeout: 10),
                          "The async server response must redraw the detail")
            XCTAssertFalse(app.buttons["detail_actions"].exists, "A stranger cannot edit the trip")
            assertMapHasContent(app, name: "foreign_trip_before_\(pass)")

            expand.tap()
            let close = app.buttons["fullscreen_map_close"].firstMatch
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            close.tap()
            XCTAssertTrue(expand.waitForExistence(timeout: 5))
            assertMapHasContent(app, name: "foreign_trip_after_\(pass)")

            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "foreign_trip_\(pass)"
            shot.lifetime = .keepAlways
            add(shot)

            app.buttons["detail_back"].firstMatch.tap()
            XCTAssertTrue(preview.waitForExistence(timeout: 5), "Back must return to the feed")
        }
        app.buttons["tab_profile"].firstMatch.tap()
        XCTAssertTrue(app.buttons["tab_home"].firstMatch.waitForExistence(timeout: 5))
    }

    /// Controls survive even when the underlying MKMapView was left in a
    /// discarded slot. Inspect the centre of the hero, excluding chrome.
    private func assertMapHasContent(_ app: XCUIApplication, name: String) {
        let rendered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            Self.mapContrast(app.screenshot()) > 0.004
        }, object: nil)
        let result = XCTWaiter.wait(for: [rendered], timeout: 5)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(result, .completed, "The hero must contain the map, not an empty black slot")
    }

    private static func mapContrast(_ screenshot: XCUIScreenshot) -> Double {
        guard let full = screenshot.image.cgImage,
              let crop = full.cropping(to: CGRect(
                x: CGFloat(full.width) * 0.08, y: CGFloat(full.height) * 0.20,
                width: CGFloat(full.width) * 0.84, height: CGFloat(full.height) * 0.16)) else { return 0 }
        let columns = 16, rows = 8
        var pixels = [UInt8](repeating: 0, count: columns * rows * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: columns, height: rows,
                                    bitsPerComponent: 8, bytesPerRow: columns * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.interpolationQuality = .medium
            context?.draw(crop, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        }
        var luminances: [Double] = []
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let red = 0.2126 * Double(pixels[i])
            let green = 0.7152 * Double(pixels[i + 1])
            let blue = 0.0722 * Double(pixels[i + 2])
            luminances.append((red + green + blue) / 255)
        }
        let mean = luminances.reduce(0, +) / Double(luminances.count)
        return (luminances.reduce(0) { $0 + pow($1 - mean, 2) } / Double(luminances.count)).squareRoot()
    }
}
