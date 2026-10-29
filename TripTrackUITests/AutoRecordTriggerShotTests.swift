import XCTest

/// «Когда начинать» на экране автозаписи (0.9.3): без магнитолы, с ней и с
/// выбором, который переживает перезапуск.
///
/// Автозапись и привязанная магнитола приходят аргументами запуска: тумблер на
/// экране зовёт системные запросы разрешений, а магнитолу в симуляторе не
/// привязать. Значения в аргументах перекрывают сохранённые, поэтому выбор
/// проверяется вторым запуском БЕЗ `-autoRecordTrigger`.
@MainActor
final class AutoRecordTriggerShotTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate() }

    func testStereoOnlyNeedsALinkedStereo() {
        open(stereos: [], trigger: "motionOrStereo")
        let stereo = app.buttons["auto_record_trigger_stereo"].firstMatch
        XCTAssertTrue(stereo.waitForExistence(timeout: 15))
        XCTAssertFalse(stereo.isEnabled, "без магнитолы «Только магнитола» не выбрать")
        XCTAssertTrue(app.buttons["auto_record_trigger_motion"].firstMatch.isSelected)
        capture("01-no-stereo")
        app.terminate()

        // Магнитолу отвязали уже после выбора: экран предупреждает и даёт
        // вернуться к движению.
        open(stereos: [], trigger: "stereoOnly")
        XCTAssertTrue(app.staticTexts["Магнитола не привязана, автозапись не начнётся"]
            .waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["auto_record_trigger_motion"].firstMatch.isEnabled)
        capture("02-stereo-missing")
    }

    func testStereoOnlyIsChosenAndRemembered() {
        open(stereos: ["Polo Radio"], trigger: "motionOrStereo")
        let stereo = app.buttons["auto_record_trigger_stereo"].firstMatch
        XCTAssertTrue(stereo.waitForExistence(timeout: 15))
        XCTAssertTrue(stereo.isEnabled)
        stereo.tap()
        XCTAssertTrue(stereo.isSelected)
        XCTAssertTrue(app.staticTexts[
            "Запись начнётся сама, когда телефон подключится к привязанной магнитоле"].exists,
            "текст тумблера больше не обещает старт по движению")
        capture("03-stereo-only")
        app.terminate()

        open(stereos: ["Polo Radio"], trigger: nil)
        let remembered = app.buttons["auto_record_trigger_stereo"].firstMatch
        XCTAssertTrue(remembered.waitForExistence(timeout: 15))
        XCTAssertTrue(remembered.isSelected, "выбор пережил перезапуск")

        // Вернуть умолчание: выбор хранится в настройках симулятора.
        app.buttons["auto_record_trigger_motion"].firstMatch.tap()
        XCTAssertTrue(app.buttons["auto_record_trigger_motion"].firstMatch.isSelected)
    }

    // MARK: - Helpers

    private func open(stereos: [String], trigger: String?) {
        app = XCUIApplication()
        let devices = stereos
            .map { #"{"uuid":"audio-\#($0)","name":"\#($0)"}"# }
            .joined(separator: ",")
        let hex = Array("[\(devices)]".utf8).map { String(format: "%02x", $0) }.joined()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-appLanguage", "ru", "-appThemeMode", "light",
            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
            "-seed-garage-demo", "-seed-garage-reset",
            "-autoRecordMode", "remind",
            "-savedBluetoothDevices", "<\(hex)>",
        ] + (trigger.map { ["-autoRecordTrigger", $0] } ?? [])
        app.launch()
        dismissSystemAlerts()
        let tab = app.buttons["tab_profile"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        tab.tap()
        let header = app.buttons["garage_header_vehicle"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 30))
        header.tap()
        reveal("vehicle_autorecord_row")
        app.descendants(matching: .any)["vehicle_autorecord_row"].firstMatch.tap()
        dismissSystemAlerts()
    }

    /// Автозапись включена аргументом, и приложение на старте спрашивает
    /// уведомления и движение. Ответ здесь не важен, важно убрать лист.
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<4 {
            var tapped = false
            for label in ["Разрешить", "Allow", "OK", "ОК"] {
                let button = springboard.buttons[label].firstMatch
                if button.exists {
                    button.tap()
                    tapped = true
                    usleep(600_000)
                    break
                }
            }
            if !tapped { usleep(500_000) }
        }
    }

    private func reveal(_ id: String) {
        let target = app.descendants(matching: .any)[id].firstMatch
        let window = app.windows.firstMatch
        for _ in 0..<12 {
            if target.exists && target.isHittable && target.frame.maxY < window.frame.maxY - 140 {
                return
            }
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.7))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -240)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(target.exists && target.isHittable, id)
    }

    private func capture(_ name: String) {
        usleep(700_000)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "autorecord-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
