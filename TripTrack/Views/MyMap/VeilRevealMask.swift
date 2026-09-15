import UIKit
import QuartzCore

/// Прорезь у машины на живой записи — дыра в экранной вуали, которая растёт
/// шестьдесят раз в секунду и не стоит при этом ни одной перерисовки тумана.
///
/// Почему маска, а не растр. До 0.7.0 дыру прожигала сама кисть
/// (`FogVeilPainter.punch(reveal:)`), а плиточный рендерер перерисовывал
/// коробку вокруг машины на каждый кадр анимации — это работало, потому что
/// тайл MapKit маленький. У экранной вуали «перерисовать» значит собрать
/// восьмимегабайтную картинку на фоновой очереди: сорок миллисекунд за кадр,
/// шестьдесят кадров в секунду. Поэтому дыра живёт маской на слое вуали —
/// она режет и растр, и ровный туман за его краем, а стоит четырёх `frame` и
/// одного градиента.
///
/// Устроена как летербокс наоборот: четыре непрозрачные полосы вокруг коробки
/// прорези плюс радиальный градиент внутри неё. Прозрачное в маске — это
/// невидимое на экране, то есть открытая карта; полосы считает та же функция,
/// которой вуаль считала дополнение до экрана, — второго ответа на этот вопрос
/// в проекте нет.
///
/// Перья те же, что у кисти (`FogVeilPainter.punchReveal`): дыра до 0.55
/// радиуса, дальше плавно до края. Разойтись этим двум нельзя — человек видит
/// их в одну и ту же секунду, когда вуаль откатывается на плиточный рендерер.
final class VeilRevealMask {
    /// Доля радиуса, до которой прорезь открыта полностью.
    static let solidFraction: CGFloat = 0.55

    let layer = CALayer()
    private let bars: [CALayer] = (0..<4).map { _ in CALayer() }
    private let hole = CAGradientLayer()

    init() {
        layer.actions = ["position": NSNull(), "bounds": NSNull(), "sublayers": NSNull()]
        for bar in bars {
            bar.backgroundColor = UIColor.white.cgColor
            bar.actions = ["position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]
            layer.addSublayer(bar)
        }
        hole.type = .radial
        // Цвет один и тот же, меняется только альфа: маску читают по альфе, а
        // интерполяция между РАЗНЫМИ цветами дала бы на полпути серость,
        // которой в дыре взяться неоткуда.
        hole.colors = [
            UIColor(white: 1, alpha: 0).cgColor,
            UIColor(white: 1, alpha: 0).cgColor,
            UIColor(white: 1, alpha: 1).cgColor,
        ]
        hole.locations = [0, NSNumber(value: Double(Self.solidFraction)), 1]
        // У радиального градиента эллипс задан прямоугольником от `startPoint`
        // до `endPoint`: центр коробки и её угол дают полуоси в половину
        // стороны, то есть ровно радиус прорези. Углы самой коробки лежат
        // дальше радиуса и остаются непрозрачными, как им и положено.
        hole.startPoint = CGPoint(x: 0.5, y: 0.5)
        hole.endPoint = CGPoint(x: 1, y: 1)
        hole.actions = ["position": NSNull(), "bounds": NSNull()]
        layer.addSublayer(hole)
    }

    /// Ставит прорезь в точку экрана. Зовётся внутри `CATransaction` с
    /// выключенными действиями — иначе каждая из пяти рамок поехала бы своей
    /// неявной анимацией и отстала бы от машины на четверть секунды.
    func update(bounds: CGRect, centre: CGPoint, radius: CGFloat) {
        layer.frame = bounds
        let box = CGRect(x: centre.x - radius, y: centre.y - radius,
                         width: radius * 2, height: radius * 2)
        hole.frame = box
        for (bar, rect) in zip(bars, Self.barsAround(bounds: bounds, hole: box)) {
            bar.frame = rect
        }
    }

    /// Четыре непрозрачные полосы вокруг коробки прорези — всё, что на экране
    /// НЕ она. Чистая функция: дыра в маске там, где её быть не должно, — это
    /// дыра в тумане, и видно её только глазами на движущейся машине.
    static func barsAround(bounds full: CGRect, hole f: CGRect) -> [CGRect] {
        let top = max(0, min(full.height, f.minY))
        let bottom = max(0, min(full.height, f.maxY))
        return [
            CGRect(x: 0, y: 0, width: full.width, height: top),
            CGRect(x: 0, y: bottom, width: full.width, height: max(0, full.height - bottom)),
            CGRect(x: 0, y: top, width: max(0, min(full.width, f.minX)),
                   height: max(0, bottom - top)),
            CGRect(x: min(full.width, max(0, f.maxX)), y: top,
                   width: max(0, full.width - max(0, f.maxX)),
                   height: max(0, bottom - top)),
        ]
    }
}
