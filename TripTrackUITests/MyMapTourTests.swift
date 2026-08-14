import XCTest

/// Screenshot tour + assertions for the 0.6.0 «Моя карта» screen.
///
/// The map is the one surface whose correctness cannot be judged from unit
/// tests: the data can be perfect while the layer hierarchy shows nothing,
/// which is exactly the state it shipped in before this rewrite («ничего не
/// видно, какие-то три точки»). So this drives the real taps — region, pull
/// up, trip — and captures each state.
final class MyMapTourTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        // Seeds a fresh store with drives across three regions and lands on
        // the Maps tab. No-op if the store already has trips.
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-seed-map-demo"]
        app.launch()
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private var win: XCUIElement { app.windows.firstMatch }

    private func tapPoint(_ dx: Double, _ dy: Double) {
        win.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
        usleep(1_400_000)
    }

    /// Opens the busiest region and pulls its card up to the full list.
    /// Regions are sorted by kilometres, so the first row is always the one
    /// the seed drives hardest.
    private func openBusiestRegionExpanded() {
        let summary = app.otherElements["mymap_summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 8))
        summary.tap()
        usleep(1_200_000)

        let row = app.otherElements["mymap_region_list"].buttons
            .matching(NSPredicate(format: "identifier != 'mymap_close'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the region list has rows")
        row.tap()
        usleep(1_500_000)

        pullPanelUp("mymap_region_card")
    }

    /// Pulls a card open by its grabber. Dragging the card BODY no longer
    /// moves the panel — that gesture used to swallow the scroll of the list
    /// inside it.
    private func pullPanelUp(_ identifier: String) {
        let panel = app.otherElements[identifier]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "\(identifier) must be up")
        panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03))
            .press(forDuration: 0.05,
                   thenDragTo: win.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32)))
        usleep(1_500_000)
    }

    /// Taps a named trip in the expanded region card, scrolling to it first.
    /// Only the top row is on screen when the card opens; tapping a row below
    /// the fold silently does nothing, and the test then measures the state it
    /// never left.
    private func tapTripRow(_ name: String) {
        let panel = app.otherElements["mymap_region_card"]
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        for _ in 0..<6 {
            if row.exists, panel.frame.contains(row.frame) { break }
            panel.swipeUp()
            usleep(700_000)
        }
        XCTAssertTrue(row.exists && panel.frame.contains(row.frame),
                      "«\(name)» must be scrolled into the trip list")
        snap("14_trips_section")
        row.tap()
        usleep(2_000_000)
    }

    func test_map_states() {
        XCTAssertTrue(app.buttons.matching(identifier: "tab_maps").firstMatch.waitForExistence(timeout: 10))
        app.buttons.matching(identifier: "tab_maps").firstMatch.tap()
        usleep(2_500_000)

        // 1 — far zoom: region fills, country chips, trip clusters, summary.
        snap("01_far")
        XCTAssertTrue(app.otherElements["mymap_summary"].waitForExistence(timeout: 8),
                      "collapsed summary must be up when nothing is selected")
        XCTAssertGreaterThan(app.otherElements.matching(identifier: "map_cluster").count, 0,
                             "far zoom must cluster trips instead of drawing hairlines")

        // 2 — tap the territory: region card.
        tapPoint(0.62, 0.42)
        snap("02_region")
        let regionCard = app.otherElements["mymap_region_card"]
        XCTAssertTrue(regionCard.waitForExistence(timeout: 5), "tapping a region opens its card")

        // 3 — pull the card up: cities and trips.
        pullPanelUp("mymap_region_card")
        snap("03_region_expanded")

        // 4 — close, then open a trip from its pin.
        let close = app.buttons.matching(identifier: "mymap_close").firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 4), "the card must offer a way out")
        close.tap()
        usleep(1_200_000)
        XCTAssertTrue(app.otherElements["mymap_summary"].waitForExistence(timeout: 4),
                      "closing a card returns to the summary")
        // Clustered pins stay in the accessibility tree with their own frames
        // even though MapKit draws only the cluster badge, so "the first pin"
        // is usually an invisible one. Tap candidates until the card opens.
        let pins = app.otherElements.matching(identifier: "map_trip_pin")
        _ = pins.firstMatch.waitForExistence(timeout: 5)
        let tripCard = app.otherElements["mymap_trip_card"]

        var opened = false
        for pin in pins.allElementsBoundByIndex where pin.isHittable {
            pin.tap()
            usleep(1_200_000)
            if tripCard.exists { opened = true; break }
            // A miss lands on the territory and opens the region card instead.
            let close = app.buttons.matching(identifier: "mymap_close").firstMatch
            if close.exists { close.tap(); usleep(800_000) }
        }

        snap("04_trip")
        XCTAssertTrue(opened, "tapping a trip pin must open the trip card")
        XCTAssertTrue(app.buttons.matching(identifier: "mymap_open_trip").firstMatch.exists,
                      "the trip card carries «Открыть поездку»")
    }

    /// The collapsed summary draws a grabber, so pulling it up has to lead
    /// somewhere: the list of every region you have opened, each row landing
    /// on that region's card.
    func test_summary_expands_to_region_list() {
        app.buttons.matching(identifier: "tab_maps").firstMatch.tap()
        usleep(2_500_000)

        let summary = app.otherElements["mymap_summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 8))
        summary.tap()
        usleep(1_200_000)
        snap("07_region_list")

        let list = app.otherElements["mymap_region_list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5), "the summary must pull up into the region list")

        // Not `buttons.firstMatch` — that is the ✕ in the panel's corner, and
        // tapping it just closed the list again.
        let row = list.buttons
            .matching(NSPredicate(format: "identifier != 'mymap_close'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 4), "the list has rows")
        row.tap()
        usleep(1_500_000)
        snap("08_region_from_list")
        XCTAssertTrue(app.otherElements["mymap_region_card"].waitForExistence(timeout: 5),
                      "a row opens that region's card")
    }

    /// Canon frame «04 · Карта · закрытый регион»: tapping a region you have
    /// never driven in still opens a card — «ещё не открыт», zero stats and
    /// the teaser pointing at your nearest trace.
    func test_locked_region_card() {
        app.buttons.matching(identifier: "tab_maps").firstMatch.tap()
        usleep(2_500_000)

        // East of the seeded territory: Stavropol Krai / Kalmykia, dark.
        tapPoint(0.90, 0.42)
        snap("06_locked_region")
        XCTAssertTrue(app.otherElements["mymap_locked_card"].waitForExistence(timeout: 5),
                      "a region with no trips still opens its own card")
    }

    /// The fog of roads has to hold up at street zoom — that is where both
    /// earlier cuts fell apart: first sixty traces of one commute stacking
    /// into a green smear, then a ground-space stroke floor turning every
    /// street into a 700 m orange blob.
    ///
    /// Getting there by guessing a screen point is what let the previous
    /// version of this test «pass» while its double-taps landed on empty
    /// steppe, so it navigates by data instead: open the busiest region, pick
    /// the repeated commute out of its trip list, and let the camera do it.
    func test_fog_at_street_zoom() {
        app.buttons.matching(identifier: "tab_maps").firstMatch.tap()
        usleep(2_500_000)
        snap("05_fog_far")

        openBusiestRegionExpanded()

        // «По городу» is seeded six times around the same city blocks, so its
        // camera lands at street zoom on roads that repeat — both halves of
        // what the ramp has to show.
        tapTripRow("По городу")
        snap("09_fog_commute")

        // Drop the card so nothing but the network is on screen, then go down
        // to the streets. Pinch, not double-tap: the map's own tap handler
        // sees each half of a double-tap as a tap on the territory, so the
        // earlier version of this re-selected the region and zoomed straight
        // back out — and still reported a pass.
        let close = app.buttons.matching(identifier: "mymap_close").firstMatch
        if close.exists { close.tap(); usleep(1_200_000) }

        win.pinch(withScale: 3, velocity: 3)
        usleep(1_500_000)
        snap("10_fog_street")
    }

    /// «Is the fog of war there or not» is not a question a screenshot settles
    /// by eye: the map is a night map either way, and the first cut cleared
    /// corridors so wide that in a real city they merged and the whole town
    /// came out opened — which looks exactly like no fog at all.
    ///
    /// So measure it. The same map, at the same camera, with and without the
    /// veil; the veiled one has to be materially darker.
    func test_fog_of_war_darkens_the_ground_you_have_not_driven() {
        let veiled = mapLuminanceAtStreetZoom(extraArguments: [])
        let bare = mapLuminanceAtStreetZoom(extraArguments: ["-no-fog-veil"])

        let drop = bare > 0 ? (1 - veiled / bare) * 100 : 0
        print("[fog] veiled=\(veiled) bare=\(bare) → \(Int(drop.rounded()))% darker")
        XCTAssertGreaterThan(bare, 0, "the map has to be rendering at all")
        XCTAssertLessThan(
            veiled, bare * 0.9,
            "the fog has to darken untravelled ground — veiled \(veiled) vs bare \(bare)"
        )
    }

    /// Drives to the seeded city loop and returns the mean luminance of the
    /// map area (the sheet and the title bar are cropped out).
    private func mapLuminanceAtStreetZoom(extraArguments: [String]) -> Double {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-seed-map-demo"]
        app.launchArguments += extraArguments
        app.launch()

        app.buttons.matching(identifier: "tab_maps").firstMatch.tap()
        usleep(2_500_000)
        openBusiestRegionExpanded()
        tapTripRow("По городу")
        let close = app.buttons.matching(identifier: "mymap_close").firstMatch
        if close.exists { close.tap(); usleep(1_500_000) }

        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = extraArguments.isEmpty ? "13_veiled" : "13_bare"
        attachment.lifetime = .keepAlways
        add(attachment)
        return Self.meanLuminance(of: shot, from: 0.12, to: 0.62)
    }

    /// Average luminance of a horizontal band of the screenshot. Drawing the
    /// crop into a single pixel is the cheapest correct way to average it.
    private static func meanLuminance(
        of screenshot: XCUIScreenshot, from: CGFloat, to: CGFloat
    ) -> Double {
        guard let full = screenshot.image.cgImage else { return 0 }
        let height = CGFloat(full.height), width = CGFloat(full.width)
        let band = CGRect(x: 0, y: height * from, width: width, height: height * (to - from))
        guard let crop = full.cropping(to: band) else { return 0 }

        var pixel: [UInt8] = [0, 0, 0, 0]
        let context = pixel.withUnsafeMutableBytes { bytes in
            CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }
        context?.interpolationQuality = .medium
        context?.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])) / 255
    }

    /// At street zoom only photo trips keep a pin, so the roads themselves
    /// have to be the way in — and a road you drove six times has to hand
    /// back all six, not whichever trip happened to be nearest. Getting one
    /// made the map feel like it held four trips.
    func test_tapping_a_repeated_road_lists_every_trip_on_it() {
        app.buttons.matching(identifier: "tab_maps").firstMatch.tap()
        usleep(2_500_000)

        openBusiestRegionExpanded()

        // «На работу» is seeded nine times over one straight road. Selecting
        // it fits that road to the padded map area, so its midpoint lands at
        // a point this test can compute rather than hunt for: centred
        // horizontally, and centred between the 130 pt top and 220 pt bottom
        // insets of `MapCameraCommand.Padding.trip`.
        tapTripRow("На работу")
        snap("11a_commute_selected")
        let close = app.buttons.matching(identifier: "mymap_close").firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 4))
        close.tap()
        usleep(1_200_000)

        let height = win.frame.height
        tapPoint(0.5, Double((height - 90) / 2 / height))
        snap("11_road_trips")

        let roadCard = app.otherElements["mymap_road_card"]
        XCTAssertTrue(roadCard.exists,
                      "tapping a road driven nine times must list those trips, not pick one")
        XCTAssertGreaterThan(
            roadCard.buttons.matching(NSPredicate(format: "identifier != 'mymap_close'")).count, 1,
            "the list must offer more than one trip to choose from"
        )

        // Picking one out of the list opens it — and it gets a pin even
        // though the seed has no photos, which at street zoom is the only
        // marker there is. Selecting a trip changes neither the pin mode nor
        // the pin count, so the rebuild used to be skipped and the marker
        // never appeared.
        roadCard.buttons.matching(NSPredicate(format: "identifier != 'mymap_close'"))
            .firstMatch.tap()
        usleep(2_000_000)
        snap("12_trip_from_road")
        XCTAssertTrue(app.otherElements["mymap_trip_card"].waitForExistence(timeout: 4),
                      "a row in the road list opens that trip")
        let pins = app.otherElements.matching(identifier: "map_trip_pin")
        XCTAssertEqual(pins.count, 1,
                       "opening a trip has to leave its pin ALONE on the map — "
                           + "one route among fifty and a dozen badges is not «open»")
        XCTAssertTrue(
            pins.allElementsBoundByIndex.contains { $0.value as? String == "selected" },
            "and that pin has to LOOK selected — MapKit re-running clustering "
                + "used to repaint it as an ordinary one"
        )
    }
}
