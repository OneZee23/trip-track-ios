import UIKit

/// Медальон печати — картинкой, чистой функцией.
///
/// Печать рисуется КОДОМ, а не лежит ассетом: видов три, символов семнадцать,
/// и в волне 5 символы меняются на гравюры — то есть рисование переписывается,
/// а имена (`SealSymbol.rawValue`) остаются. Ассетами это была бы пятьдесят
/// одна картинка в трёх масштабах, из которых половина никогда не встретится
/// одному человеку.
///
/// Функция ЧИСТАЯ (ни карты, ни языка, ни базы) по той же причине, по которой
/// чисты `AutoTripPolicy` и `JourneyEditSheet.startBounds`: цвет кольца — это
/// единственное, чем вид находки отличается на карте, и проверять его глазами
/// на тумане значит не проверять вовсе. `SealPainterTests` читает пиксель.
///
/// Кэш — по (вид, символ, масштаб), `NSCache`: `MKAnnotationView` пересобирает
/// картинку на каждом переиспользовании, а их на «Атласе» столько, сколько
/// печатей на экране. Размер в ключ не входит — он у печати один
/// (`SealPainter.size`), и параметром остался ради теста.
enum SealPainter {

    /// Диаметр медальона на экране. Постоянный: печать не растёт с зумом —
    /// она метка, а не объект на земле.
    static let size: CGFloat = 26

    /// Тёмный диск — тот же «вдавленный в туман» цвет, что у чернил карты.
    static let disc = UIColor(red: 0x14 / 255, green: 0x16 / 255, blue: 0x21 / 255, alpha: 1)

    /// Кольцо задаёт ВИД находки, и эти три цвета — контракт со спекой (§2):
    /// золото — авторский секрет, бирюза — загадка, тёплый — веха. Живут
    /// здесь, а не у каждого вью: их читают медальон, кластер и пунктирный
    /// круг подсказки, и разъехаться им нельзя.
    static func ring(for kind: DiscoveryKind) -> UIColor {
        switch kind {
        case .secret:    return UIColor(red: 0xF5 / 255, green: 0xBE / 255, blue: 0x1E / 255, alpha: 1)
        case .riddle:    return UIColor(red: 0x50 / 255, green: 0xBE / 255, blue: 0xD2 / 255, alpha: 1)
        case .milestone: return UIColor(red: 0xF0 / 255, green: 0xA0 / 255, blue: 0x70 / 255, alpha: 1)
        }
    }

    /// Толщина кольца в точках.
    static let ringWidth: CGFloat = 2

    private static let cache = NSCache<NSString, UIImage>()

    /// Медальон: тёмный диск с внутренней тенью, кольцо цветом вида, символ
    /// белым в 70 %.
    ///
    /// `scale` — параметром, а не `UIScreen.main.scale`: чистая функция не
    /// имеет права спрашивать экран, а тест обязан получить ту же картинку на
    /// любом симуляторе.
    static func image(
        kind: DiscoveryKind,
        symbol: SealSymbol,
        size: CGFloat = SealPainter.size,
        scale: CGFloat
    ) -> UIImage {
        let key = "\(kind.rawValue)|\(symbol.rawValue)|\(size)|\(scale)" as NSString
        if let hit = cache.object(forKey: key) { return hit }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
            let cg = context.cgContext
            // Диск — по кольцевой окружности, чтобы кольцо ложилось ПО КРАЮ
            // диска, а не поверх тумана: полупрозрачного края у печати нет.
            let ringRect = bounds.insetBy(dx: ringWidth / 2, dy: ringWidth / 2)
            let disc = UIBezierPath(ovalIn: ringRect)
            SealPainter.disc.setFill()
            disc.fill()

            // Внутренняя тень: тем же приёмом, что у вдавленных плашек, —
            // клип по диску и мягкий штрих ВНУТРЬ от края. Отдельного API у
            // CoreGraphics для неё нет.
            cg.saveGState()
            disc.addClip()
            cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                         color: UIColor.black.withAlphaComponent(0.85).cgColor)
            let inner = UIBezierPath(ovalIn: ringRect.insetBy(dx: -1, dy: -1))
            inner.lineWidth = 3
            UIColor.black.withAlphaComponent(0.9).setStroke()
            inner.stroke()
            cg.restoreGState()

            let ring = UIBezierPath(ovalIn: ringRect)
            ring.lineWidth = ringWidth
            SealPainter.ring(for: kind).setStroke()
            ring.stroke()

            let glyphSize = size * 0.44
            let configuration = UIImage.SymbolConfiguration(pointSize: glyphSize, weight: .medium)
            if let glyph = UIImage(systemName: symbol.rawValue, withConfiguration: configuration)?
                .withTintColor(UIColor.white.withAlphaComponent(0.7), renderingMode: .alwaysOriginal) {
                let box = CGRect(
                    x: (size - glyph.size.width) / 2,
                    y: (size - glyph.size.height) / 2,
                    width: glyph.size.width,
                    height: glyph.size.height
                )
                glyph.draw(in: box)
            }
        }
        cache.setObject(image, forKey: key)
        return image
    }
}
