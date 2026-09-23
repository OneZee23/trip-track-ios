import XCTest

/// Карта-герой обязана ПЕРЕЖИТЬ поход на полный экран и обратно.
///
/// Владелец на устройстве 23 сентября: «нажимаю на полноэкранный формат карты,
/// захожу в неё, потом выхожу, попадаю в деталку — и карта уже просто чёрный
/// прямоугольник». Металл, на который карту поездки перевели накануне, тут ни
/// при чём — со снятым `FogMetalAvailability.isEnabled` прямоугольник ровно
/// тот же. Разбирая полноэкранное представление, SwiftUI снимал общую
/// `MKMapView` с родителя, которым к тому времени был уже слот героя (см.
/// `TripMapSlotView`).
///
/// Почему кадром, а не состоянием. «Карта видна» — это ровно про то, что на
/// экране: и хост, и координатор, и `visibleMapRect` у пустого героя остаются
/// правильными, отвечать на вопрос им нечем. А `FullscreenMapExpansionShotTests`
/// рядом кадры снимает, но ничего про них не утверждает — и эту поломку
/// пропустил молча, потому что его последний тап уходит в просмотрщик снимка.
final class TripHeroAfterFullscreenTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>",
            "-seed-map-demo", "-seed-places-rich"
        ]
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func test_hero_map_survives_the_trip_to_fullscreen_and_back() {
        let profile = app.buttons.matching(identifier: "tab_profile").firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 15), "нет входа в «Я»")
        profile.tap()
        usleep(3_000_000)

        let row = app.historyTripCells.firstMatch
        var attempts = 0
        while !row.exists && attempts < 6 {
            app.swipeUp(velocity: .slow)
            usleep(900_000)
            attempts += 1
        }
        XCTAssertTrue(row.waitForExistence(timeout: 8), "в истории нет ни одной поездки")
        row.tap()
        usleep(5_000_000)

        // Точка отсчёта: насколько герой РАЗНЫЙ до похода. Средний свет тут
        // не годится вовсе — пустая тёмная плашка и ночная карта светят почти
        // одинаково, и первая редакция этого теста именно поэтому прошла на
        // сломанном экране. Разброс различает их сразу: у карты есть маршрут,
        // подписи и подпись Apple, у плашки нет ничего.
        let before = Self.heroContrast(XCUIScreen.main.screenshot())
        snap("hero_before")
        XCTAssertGreaterThan(before, Self.flat,
                             "герой пустой ещё ДО полного экрана — сломано раньше")

        let expand = app.buttons.matching(identifier: "detail_map_expand").firstMatch
        XCTAssertTrue(expand.waitForExistence(timeout: 8), "нет кнопки «развернуть»")
        expand.tap()

        let close = app.buttons.matching(identifier: "fullscreen_map_close").firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 8), "полный экран не открылся")
        usleep(1_500_000)
        close.tap()
        // Пружина возврата — 0.38/0.9; двух секунд хватает и ей, и кадру,
        // который карта обязана нарисовать, вернувшись в слот.
        usleep(2_000_000)

        let after = Self.heroContrast(XCUIScreen.main.screenshot())
        snap("hero_after")
        XCTAssertGreaterThan(after, Self.flat,
                             "на месте карты пустой прямоугольник: разброс \(after)")
        XCTAssertGreaterThan(after, before * 0.5,
                             "герой обеднел вдвое после возврата: было \(before), стало \(after)")
    }

    // MARK: Кадр

    /// Ниже этого разброса прямоугольник однотонный, то есть карты в нём нет.
    /// Замер на исправном экране — около 0.05, на сломанном — 0.002.
    private static let flat = 0.012

    /// Разброс света по полосе, в которой живёт карта-герой. Границы взяты с
    /// запасом внутрь: сверху вуаль статус-бара, снизу — карточка с деталями.
    private static func heroContrast(_ shot: XCUIScreenshot) -> Double {
        contrast(of: shot, from: 0.12, to: 0.38)
    }

    /// Среднеквадратичное отклонение света по сетке 16×8.
    ///
    /// Полоса сжимается в такую сетку одним `draw` — это и усреднение внутри
    /// каждой клетки, и дешёвый способ прочитать их все разом.
    private static func contrast(
        of screenshot: XCUIScreenshot, from: CGFloat, to: CGFloat
    ) -> Double {
        guard let full = screenshot.image.cgImage else { return 0 }
        let height = CGFloat(full.height), width = CGFloat(full.width)
        let band = CGRect(x: 0, y: height * from, width: width, height: height * (to - from))
        guard let crop = full.cropping(to: band) else { return 0 }

        let cols = 16, rows = 8
        var pixels = [UInt8](repeating: 0, count: cols * rows * 4)
        let context = pixels.withUnsafeMutableBytes { bytes in
            CGContext(
                data: bytes.baseAddress, width: cols, height: rows, bitsPerComponent: 8,
                bytesPerRow: cols * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }
        context?.interpolationQuality = .medium
        context?.draw(crop, in: CGRect(x: 0, y: 0, width: cols, height: rows))

        var lums: [Double] = []
        for i in stride(from: 0, to: pixels.count, by: 4) {
            lums.append((0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1])
                         + 0.0722 * Double(pixels[i + 2])) / 255)
        }
        guard !lums.isEmpty else { return 0 }
        let mean = lums.reduce(0, +) / Double(lums.count)
        let variance = lums.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(lums.count)
        return variance.squareRoot()
    }

    private func snap(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
