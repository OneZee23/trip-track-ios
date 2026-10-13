import XCTest

/// «Карта видна» — вопрос про КАДР, а не про состояние: у пустого героя и
/// хост, и координатор, и `visibleMapRect` остаются правильными, отвечать
/// им нечем (см. `TripHeroAfterFullscreenTests`). Здесь лежит сам замер,
/// чтобы два сценария возврата к герою — свой полный экран и пуш чужого
/// экрана поверх — меряли ОДНИМ числом и одним порогом. Разойдясь, они
/// однажды разошлись бы и в ответе.
enum HeroMapProbe {
    /// Ниже этого разброса прямоугольник однотонный, то есть карты в нём нет.
    /// Замер на исправном экране — около 0.05, на сломанном — 0.002.
    static let flat = 0.012

    /// Насколько кадр героя вправе отличаться от себя же до похода. Замер на
    /// исправном экране — около 0.01, на съехавшей камере — 0.1 и выше.
    static let maxDrift = 0.02

    /// Свет по клеткам полосы, в которой живёт карта-герой. Границы взяты с
    /// запасом внутрь: сверху вуаль статус-бара, снизу — карточка с деталями.
    static func heroGrid(_ shot: XCUIScreenshot) -> [Double] {
        grid(of: shot, from: 0.12, to: 0.38)
    }

    /// Среднеквадратичное отклонение света по клеткам. Средний свет тут не
    /// годится вовсе: пустая тёмная плашка и ночная карта светят одинаково.
    static func contrast(_ lums: [Double]) -> Double {
        guard !lums.isEmpty else { return 0 }
        let mean = lums.reduce(0, +) / Double(lums.count)
        let variance = lums.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(lums.count)
        return variance.squareRoot()
    }

    /// Среднее расхождение двух кадров по клеткам.
    static func difference(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        return zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) } / Double(a.count)
    }

    /// Полоса, сжатая в сетку 16×8 одним `draw`: это и усреднение внутри
    /// каждой клетки, и дешёвый способ прочитать их все разом.
    static func grid(
        of screenshot: XCUIScreenshot, from: CGFloat, to: CGFloat,
        columns: Int = 16, rows: Int = 8
    ) -> [Double] {
        guard let full = screenshot.image.cgImage else { return [] }
        let height = CGFloat(full.height), width = CGFloat(full.width)
        let band = CGRect(x: 0, y: height * from, width: width, height: height * (to - from))
        guard let crop = full.cropping(to: band) else { return [] }

        let cols = columns
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
        return lums
    }
}
