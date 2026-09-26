import XCTest

/// The journey destination is conditionally registered on a background
/// anchor so ownership loading cannot replace the trip's map subtree.
/// Exercise that destination itself, including returning to the same trip.
///
/// Возврат проверяется КАДРОМ, а не наличием кнопки: у пустого героя и хост,
/// и координатор, и `visibleMapRect` остаются правильными — тем же, чем
/// `TripHeroAfterFullscreenTests` ловит свой полный экран. Пуш чужого экрана
/// поверх — второй путь к тому же вопросу, и мерить его надо тем же числом
/// (`HeroMapProbe`), иначе сценарий снимает кадр и молчит о нём.
final class TripJourneyNavigationTests: XCTestCase {
    func testOwnTripCanOpenItsJourneyAndReturnToItsMap() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>",
            "-seed-map-demo", "-seed-journey-demo", "-debug-foreign-trip"
        ]
        app.launch()

        tap("tab_profile", in: app, timeout: 20)

        // The seeded journey is about twelve days back in the history,
        // behind the recent city trips. Its legs are folded into this card.
        let journey = app.buttons.matching(identifier: "profile_journey_card").firstMatch
        let window = app.windows.firstMatch
        for _ in 0..<30 {
            let tabTop = app.buttons["tab_profile"].firstMatch.frame.minY
            if journey.exists, journey.isHittable, journey.frame.maxY < tabTop { break }
            window.swipeUp()
        }
        XCTAssertTrue(journey.exists && journey.isHittable, "Seeded journey must appear in profile history")
        journey.tap()
        XCTAssertTrue(visible("journey_map_expand", in: app).waitForExistence(timeout: 10))

        // Use a real journey leg, not a title match that could pick a seeded
        // duplicate outside the journey and open the composer instead.
        let leg = app.buttons.matching(identifier: "journey_leg_row").firstMatch
        for _ in 0..<15 {
            if leg.exists, leg.isHittable { break }
            window.swipeUp()
        }
        XCTAssertTrue(leg.exists && leg.isHittable, "Seeded journey must expose its legs")
        leg.tap()
        waitForVisible("detail_map_expand", in: app)
        // Карта поездки рисует первый кадр уже после того, как её кнопка
        // стала доступна; замер до этого читал бы ещё пустую рамку.
        usleep(4_000_000)
        let beforeGrid = HeroMapProbe.heroGrid(XCUIScreen.main.screenshot())
        let before = HeroMapProbe.contrast(beforeGrid)
        attach(app, name: "own_trip_before_journey")
        XCTAssertEqual(app.maps.count, 1, "у экрана поездки обязана быть ровно одна карта")
        XCTAssertGreaterThan(before, HeroMapProbe.flat,
                             "герой пустой ещё ДО путешествия — сломано раньше: \(before)")

        tap("detail_actions", in: app)
        tap("detail_action_journey", in: app)

        // This is the changed navigationDestination on TripDetailView.
        // A visible journey map distinguishes a real push from a dismissed
        // menu, an ignored binding, or the journey composer sheet.
        waitForVisible("journey_map_expand", in: app)
        attach(app, name: "journey_opened_from_own_trip")
        tap("journey_map_expand", in: app)
        tap("fullscreen_map_close", in: app)
        waitForVisible("journey_map_expand", in: app)
        tap("detail_back", in: app)

        waitForVisible("detail_map_expand", in: app)
        XCTAssertFalse(app.buttons["tab_home"].exists, "Back from journey must return to trip detail")
        // Столько же, сколько отмерено первому кадру выше: вопрос «карта
        // вернулась» не должен зависеть от того, кто успел раньше.
        usleep(4_000_000)
        let afterGrid = HeroMapProbe.heroGrid(XCUIScreen.main.screenshot())
        let after = HeroMapProbe.contrast(afterGrid)
        attach(app, name: "own_trip_after_journey_back")
        // Карта пропадала из ИЕРАРХИИ целиком, а не просто не рисовалась:
        // `onWindowChange` считал накрывший экран уходом и звал `tearDown`.
        XCTAssertEqual(app.maps.count, 1, "карта не вернулась в дерево после путешествия")
        print("JOURNEY_HERO_BEFORE \(before) AFTER \(after)")
        XCTAssertGreaterThan(after, HeroMapProbe.flat,
                             "на месте карты пустой прямоугольник: разброс \(after)")
        XCTAssertGreaterThan(after, before * 0.5,
                             "герой обеднел вдвое после путешествия: было \(before), стало \(after)")
    }

    /// A nested journey can leave an older journey view in the navigation
    /// hierarchy. Prefer the visible button instead of an offscreen duplicate.
    private func visible(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let matches = app.buttons.matching(identifier: identifier)
        return matches.allElementsBoundByIndex.first(where: \.isHittable) ?? matches.firstMatch
    }

    private func waitForVisible(_ identifier: String, in app: XCUIApplication, timeout: TimeInterval = 10) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let button = self.visible(identifier, in: app)
            return button.exists && button.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed, identifier)
    }

    private func tap(_ identifier: String, in app: XCUIApplication, timeout: TimeInterval = 10) {
        waitForVisible(identifier, in: app, timeout: timeout)
        visible(identifier, in: app).tap()
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
