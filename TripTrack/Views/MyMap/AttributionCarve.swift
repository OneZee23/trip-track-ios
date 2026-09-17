import UIKit
import MapKit
import os

/// Вырез в мгле под атрибуцией Apple — вместо светлой плиты под ней.
///
/// Плита была и ушла 17 сентября. Она честно возвращала логотипу и «Legal»
/// светлый фон, но на устройстве читалась как отдельный блок, наехавший на
/// край листа: наша плашка поверх чужой вью. Владелец увидел именно это.
///
/// Правильный ответ проще: не подкладывать Apple свой фон, а УБРАТЬ оттуда
/// свой туман. Мгла вырезается скруглённым прямоугольником с мягким краем, и
/// подпись садится на настоящую карту Apple — ровно на тот фон, под который
/// MapKit её и красит.
///
/// Ни одного приватного метода: только `subviews` и имя класса, как у вуали.
/// Не нашли атрибуцию — вырезать нечего, и карта возвращается в ночную:
/// видимость важнее полярности.
@MainActor
enum AttributionCarve {

    /// Поле вокруг атрибуции и ширина растушёвки — решение контроллера.
    static let padding: CGFloat = 6
    static let feather: CGFloat = 8
    static let corner: CGFloat = 8

    /// Сколько проходов разметки ждём атрибуцию: она появляется в дереве
    /// карты не обязательно к первому.
    static let maxTries = 20

    private static let log = Logger(subsystem: "com.onezee.TripTrack", category: "attribution")
    private static var loggedFallback = false

    /// Подстрок ТРИ, и каждая оплачена наблюдением. На iOS 18 атрибуция — это
    /// одна вью `MKAppleLogoLabel` (та самая «` Maps`»), отдельной «Legal» в
    /// этой конфигурации нет вовсе; в других сборках рядом с ней живёт ссылка
    /// со словом `Attribution` или `Legal` в имени. Имена приватные, и Apple
    /// вправе их переписать — поэтому пустой ответ это законный случай.
    static let nameNeedles = ["Attribution", "Logo", "Legal"]

    /// Вьюхи атрибуции — по ПОДСТРОКЕ имени класса, обходом ВШИРЬ.
    static func attributionViews(in root: UIView) -> [UIView] {
        var queue = root.subviews
        var head = 0
        var found: [UIView] = []
        while head < queue.count {
            let view = queue[head]
            head += 1
            let name = NSStringFromClass(type(of: view))
            if nameNeedles.contains(where: name.contains) {
                found.append(view)
                continue
            }
            queue.append(contentsOf: view.subviews)
        }
        return found
    }

    /// Коробка выреза в координатах `space` — объединение всех вьюх атрибуции
    /// с полем. `nil` — вырезать нечего.
    static func carveRect(in root: UIView, space: UIView) -> CGRect? {
        var union = CGRect.null
        for view in attributionViews(in: root) where !view.isHidden && view.bounds.width > 0 {
            union = union.union(view.convert(view.bounds, to: space))
        }
        guard !union.isNull, union.width > 1, union.height > 1 else { return nil }
        return union.insetBy(dx: -padding, dy: -padding)
    }

    /// Про откат рассказываем один раз за запуск.
    static func noteFallback() {
        guard !loggedFallback else { return }
        loggedFallback = true
        log.notice("атрибуция не найдена — карта возвращается в ночную")
    }
}

/// Маска вуали с вырезом: всё непрозрачно, кроме скруглённого окна под
/// атрибуцией.
///
/// Устроена по тому же принципу, что `VeilRevealMask`: четыре непрозрачные
/// полосы вокруг коробки плюс картинка с мягким окном внутри неё. Прозрачное
/// в маске — это невидимое на экране, то есть открытая карта Apple. Картинка
/// перерисовывается ТОЛЬКО когда коробка меняет размер (разметка, высота
/// листа, поворот), а не на кадр движения карты.
final class VeilCarveMask {
    let layer = CALayer()
    private let bars: [CALayer] = (0..<4).map { _ in CALayer() }
    private let window = CALayer()
    private var drawnSize: CGSize = .zero

    init() {
        layer.actions = ["position": NSNull(), "bounds": NSNull(), "sublayers": NSNull()]
        for bar in bars {
            bar.backgroundColor = UIColor.white.cgColor
            bar.actions = ["position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]
            layer.addSublayer(bar)
        }
        window.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull()]
        layer.addSublayer(window)
    }

    /// Ставит вырез. `carve` — уже с полем, в координатах вуали.
    func update(bounds: CGRect, carve: CGRect) {
        layer.frame = bounds
        let box = carve.insetBy(dx: -AttributionCarve.feather, dy: -AttributionCarve.feather)
        window.frame = box
        if drawnSize != box.size {
            window.contents = VeilCarveMask.windowImage(size: box.size)
            window.contentsScale = UIScreen.main.scale
            drawnSize = box.size
        }
        for (bar, rect) in zip(bars, VeilRevealMask.barsAround(bounds: bounds, hole: box)) {
            bar.frame = rect
        }
    }

    /// Белое поле с мягким скруглённым окном посередине.
    ///
    /// Кольцами, каждое своей альфой: у края картинки мгла целая, у самой
    /// коробки выреза её нет, между ними ровный спад. Два способа, которые не
    /// работают и проверены падением теста: `.clear` с глобальной альфой
    /// (режим обнуляет пиксель целиком и альфу не слушает — выходит
    /// ступенька) и наложение одинаковых полупрозрачных слоёв друг на друга
    /// (сумма даёт 0.65 вместо единицы, и по краю остаётся щель).
    static func windowImage(size: CGSize, steps: Int = 10) -> CGImage? {
        guard size.width > 1, size.height > 1, steps > 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let bounds = CGRect(origin: .zero, size: size)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor.white.cgColor)
            // Углы картинки лежат ЗА скруглением самого внешнего кольца, и
            // без этой заливки они остаются пустыми — то есть в мгле
            // появляются четыре дырки по углам выреза.
            cg.saveGState()
            cg.addRect(bounds)
            cg.addPath(UIBezierPath(
                roundedRect: bounds, cornerRadius: AttributionCarve.corner).cgPath)
            cg.clip(using: .evenOdd)
            cg.fill(bounds)
            cg.restoreGState()
            for step in 0..<(steps - 1) {
                let t = CGFloat(step) / CGFloat(steps - 1)
                let next = CGFloat(step + 1) / CGFloat(steps - 1)
                let outer = bounds.insetBy(dx: AttributionCarve.feather * t,
                                           dy: AttributionCarve.feather * t)
                let inner = bounds.insetBy(dx: AttributionCarve.feather * next,
                                           dy: AttributionCarve.feather * next)
                guard inner.width > 0, inner.height > 0 else { continue }
                cg.saveGState()
                cg.addPath(UIBezierPath(
                    roundedRect: outer, cornerRadius: AttributionCarve.corner).cgPath)
                cg.addPath(UIBezierPath(
                    roundedRect: inner, cornerRadius: AttributionCarve.corner).cgPath)
                cg.clip(using: .evenOdd)
                cg.setAlpha(1 - t)
                cg.fill(bounds)
                cg.restoreGState()
            }
        }
        return image.cgImage
    }
}
