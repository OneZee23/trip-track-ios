import XCTest

/// «Я» под строкой состояния (0.8.9). Экран — корень вкладки без своей шапки:
/// наверху сразу карточка профиля. Пока её никто не трогает, она стоит ниже
/// часов, но стоило пролистать — «Гараж · Достижения · Клубы», заголовок
/// «Истории» и карты поездок шли прямо под часы, связь и заряд, и в тёмной
/// теме светлые карты гасили белые глифы (ревью на iPhone SE и на 16 Pro Max,
/// 12 окт 2026). На соседних экранах этого нет: их шапку ставит
/// `safeAreaInset`, и она сама закрывает строку состояния.
///
/// Вопрос здесь про КАДР: в дереве доступности строки состояния нет, и
/// «что под ней видно» состоянием не спросить. Меряется разброс света в
/// полосе строки состояния на долистанном экране — там, где нет глифов:
/// подложка цвета страницы даёт ровную полосу, проступающие карточки —
/// пёструю.
@MainActor
final class MeStatusBarBackdropTests: XCTestCase {
    private var app: XCUIApplication!

    /// Ниже этого полоса однотонная. Замер на SE 12 окт: на исправном экране
    /// (полоса — один цвет страницы) ровно 0; текст раздела под часами —
    /// 0.05–0.06; светлая однородная карта поездки под часами — 0.014, поэтому
    /// порог ниже её, а сторож дважды смотрит разные места прокрутки.
    private static let flat = 0.008

    override func setUpWithError() throws { continueAfterFailure = false }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testScrolledMeKeepsTheStatusBarOnPageColorLight() {
        assertBackdrop(theme: "light")
    }

    func testScrolledMeKeepsTheStatusBarOnPageColorDark() {
        assertBackdrop(theme: "dark")
    }

    private func assertBackdrop(theme: String) {
        app = XCUIApplication()
        app.launchArguments = [
            "-appLanguage", "ru", "-AppleLanguages", "(ru)", "-appThemeMode", theme,
            "-hasCompletedOnboarding", "<true/>",
            "-seed-map-demo", "-seed-places-demo",
        ]
        app.launch()
        let tab = app.buttons["tab_profile"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 40))
        tab.tap()
        XCTAssertTrue(app.buttons["profile_avatar"].firstMatch.waitForExistence(timeout: 15))
        let resting = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        resting.name = "me_resting_\(theme)"
        resting.lifetime = .keepAlways
        add(resting)

        // Под строкой состояния должно побывать разное: текст разделов, потом
        // карты поездок. Светлая карта бывает почти однородной и подложку не
        // выдаёт, а текст выдаёт всегда — поэтому кадров несколько.
        let window = app.windows.firstMatch
        let barHeight = statusBarHeight()
        let height = window.frame.height
        var worst = 0.0
        for step in 0..<4 {
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -260)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
            usleep(800_000)
            let shot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "me_scrolled_\(theme)_\(step)"
            attachment.lifetime = .keepAlways
            add(attachment)
            // Полоса строки состояния: от 20 до 80 % её высоты, то есть целиком
            // внутри неё. По ширине — 0.58…0.70: на SE это между часами (по
            // центру) и батареей, на iPhone с Dynamic Island — между островом
            // и значками. Свободен от глифов на обоих (замер 12 окт).
            let lums = Self.band(shot, x0: 0.58, x1: 0.70,
                                 y0: barHeight * 0.2 / height, y1: barHeight * 0.8 / height)
            worst = max(worst, HeroMapProbe.contrast(lums))
        }
        XCTAssertLessThan(worst, Self.flat,
                          "content shows under the status bar (\(theme)): spread \(worst)")
    }

    /// Высота строки состояния в точках — по SpringBoard, иначе по ширине
    /// окна: у SE (375) — 20, у телефонов с вырезом — около 54.
    private func statusBarHeight() -> CGFloat {
        let bar = XCUIApplication(bundleIdentifier: "com.apple.springboard").statusBars.firstMatch
        if bar.exists, bar.frame.height > 0 { return bar.frame.height }
        return app.windows.firstMatch.frame.width <= 375 ? 20 : 54
    }

    /// Свет прямоугольника скриншота в долях ширины и высоты, сжатый в сетку
    /// 8×2 — тем же способом, что полоса героя в `HeroMapProbe`.
    private static func band(_ shot: XCUIScreenshot, x0: CGFloat, x1: CGFloat,
                             y0: CGFloat, y1: CGFloat) -> [Double] {
        guard let full = shot.image.cgImage else { return [] }
        let w = CGFloat(full.width), h = CGFloat(full.height)
        let rect = CGRect(x: w * x0, y: h * y0, width: w * (x1 - x0), height: h * (y1 - y0))
        guard let crop = full.cropping(to: rect.integral) else { return [] }
        let cols = 8, rows = 2
        var pixels = [UInt8](repeating: 0, count: cols * rows * 4)
        let context = pixels.withUnsafeMutableBytes { bytes in
            CGContext(data: bytes.baseAddress, width: cols, height: rows, bitsPerComponent: 8,
                      bytesPerRow: cols * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        context?.interpolationQuality = .medium
        context?.draw(crop, in: CGRect(x: 0, y: 0, width: cols, height: rows))
        var lums: [Double] = []
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = 0.2126 * Double(pixels[i])
            let g = 0.7152 * Double(pixels[i + 1])
            let b = 0.0722 * Double(pixels[i + 2])
            lums.append((r + g + b) / 255)
        }
        return lums
    }
}
