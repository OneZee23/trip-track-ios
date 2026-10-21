import UIKit
import MapKit

/// Жилка открытого и выбранный маршрут — ВЕКТОРОМ поверх растра, а не
/// пикселями внутри него.
///
/// Почему их пришлось вынуть из растра. Растр вуали рисуется в полтора
/// пикселя на точку (`FogVeilView.renderScale`): у тумана нет ни одной резкой
/// границы, кроме перьевого края коридора, а память и время отрисовки растут
/// квадратом. Для дымки, облаков и рампы этого хватает с запасом — а жилка
/// это тонкая ЛИНИЯ, и половинное разрешение на ней видно глазами:
/// диагональная дорога идёт лесенкой в два экранных пикселя на ступень
/// («линии пиксельные, надо сгладить» — владелец на устройстве, 18 сентября).
///
/// Поднять весь растр до экранного масштаба нельзя — это учетверение памяти
/// (16 МБ → 64 МБ на «Атласе»), и растров живёт два. Поэтому линия уходит на
/// свой слой: `CAShapeLayer` в системе координат РАСТРА, то есть едущий за
/// картой тем же аффинным преобразованием, что и туман под ним, и при этом
/// растеризуемый в экранном масштабе. Во время жеста он ничего не
/// пересчитывает — ровно как растр; в покое он чёткий.
///
/// В сам растр жилка по-прежнему умеет рисоваться (`FogVeilBitmap.render`,
/// параметр `vein`): постеру «Поделиться» слоёв не отдать, он собирает одну
/// картинку. Плиточный откат рисует её своим `RouteVeinRenderer` — тем же
/// индексом и теми же ширинами.
enum FogVeilVein {

    /// Один проход пера: путь уже в координатах растра (точки экрана от его
    /// левого верхнего угла), ширина и цвет — в них же.
    struct Stroke {
        var path: CGPath
        var width: CGFloat
        var color: UIColor
    }

    /// Проходы для этого растра.
    ///
    /// Чистая функция и зовётся вне главного потока: она перебирает бакеты
    /// индекса и копирует пути, а это единственная работа, которую слой
    /// делает за кадр.
    ///
    /// Ширины берутся у `RouteVeinRenderer` — того же источника, что у
    /// плиточного отката и у постера: разъехаться этим трём нельзя, иначе
    /// потеря места в дереве меняла бы толщину линии.
    static func strokes(
        rect: MKMapRect, sizePoints: CGSize,
        chunks: MapPathChunks?, selected: [MKMapPoint],
        palette: FogVeilPainter.Palette = FogVeilPainter.palette
    ) -> [Stroke] {
        guard rect.width > 0, rect.height > 0, sizePoints.width > 0 else { return [] }
        // Масштаб растра: точек экрана на точку карты. Он же `zoomScale` —
        // ровно тот, которым меряет ширины плиточный рендерер, поэтому
        // экранные ширины в координатах растра берутся как есть.
        let zoomScale = MKZoomScale(sizePoints.width / CGFloat(rect.width))
        let lod = FogVeilRenderer.lod(for: zoomScale)
        // Один снимок цвета на весь набор проходов: он же лежит в рендерере
        // (`RouteVeinRenderer.veinColor`), и спрашивать его дважды значит
        // дважды сходить в `UserDefaults` за одним и тем же ответом.
        let colors = RouteVeinRenderer.resolvedColors(palette: palette)
        // Сдвиг к левому верхнему углу растра, затем масштаб: `p' = (p − o)·z`.
        let transform = CGAffineTransform(scaleX: CGFloat(zoomScale), y: CGFloat(zoomScale))
            .translatedBy(x: CGFloat(-rect.minX), y: CGFloat(-rect.minY))
        var out: [Stroke] = []

        if let chunks {
            let casedWidth = RouteVeinRenderer.width(for: lod)
                + (colors.networkCasing != nil ? RouteVeinRenderer.casingExtra : 0)
            let widest = max(casedWidth,
                             RouteVeinRenderer.halo(for: lod)?.width ?? 0) / CGFloat(zoomScale)
            let paths = chunks.visiblePaths(
                in: rect.insetBy(dx: -Double(widest) - 1, dy: -Double(widest) - 1),
                zoomScale: zoomScale)
            if !paths.isEmpty {
                let net = CGMutablePath()
                for path in paths {
                    Self.appendThinned(path, to: net, transform: transform, minStep: Self.minStepPoints)
                }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-trace-vein") {
                    var before = 0, after = 0, runs = 0
                    for path in paths { path.applyWithBlock { _ in before += 1 } }
                    net.applyWithBlock { e in after += 1; if e.pointee.type == .moveToPoint { runs += 1 } }
                    NSLog("VEINTRACE lod=\(lod) zoom=\(zoomScale) before=\(before) after=\(after) runs=\(runs)")
                }
                #endif
                // Ореол — первым: сердцевина ложится поверх него.
                if let halo = RouteVeinRenderer.halo(for: lod) {
                    let metre = MKMapPointsPerMeterAtLatitude(
                        MKMapPoint(x: rect.midX, y: rect.midY).coordinate.latitude)
                    let ceiling = FogVeilRenderer.corridorWidth(zoomScale: zoomScale, metre: metre)
                        * 1.2 * CGFloat(zoomScale)
                    out.append(Stroke(
                        path: net, width: min(halo.width, ceiling),
                        color: colors.network.withAlphaComponent(halo.alpha)))
                }
                if let casing = colors.networkCasing {
                    out.append(Stroke(path: net, width: casedWidth, color: casing))
                }
                out.append(Stroke(
                    path: net, width: RouteVeinRenderer.width(for: lod),
                    color: colors.network.withAlphaComponent(0.9)))
            }
        }

        if selected.count > 1 {
            let raw = CGMutablePath()
            raw.move(to: CGPoint(x: selected[0].x, y: selected[0].y))
            for point in selected.dropFirst() {
                raw.addLine(to: CGPoint(x: point.x, y: point.y))
            }
            var matrix = transform
            if let line = raw.copy(using: &matrix) {
                out.append(Stroke(
                    path: line,
                    width: RouteVeinRenderer.selectedWidth + RouteVeinRenderer.casingExtra,
                    color: colors.casing))
                out.append(Stroke(
                    path: line, width: RouteVeinRenderer.selectedWidth,
                    color: colors.selected))
            }
        }
        return out
    }

    /// Шаг, ближе которого соседние вершины сети не рисуются, в точках экрана.
    ///
    /// Сеть хранится на шаге своего уровня детали (75 м, 250 м, 1 км), и на
    /// масштабе страны километровый шаг — 0.17 экранной точки: чужая карта на
    /// 25 тысяч км (13 окт 2026) отдавала слою `CAShapeLayer` 53 тысячи
    /// вершин, которые система заново раскладывала на каждом растре во время
    /// щипка, — отсюда рывки и нагрев. Линия сети толщиной 2.2–3 точки, ореол
    /// 8–10: излом короче точки глаз на ней не различает, поэтому картинка
    /// та же, а вершин в разы меньше.
    static let minStepPoints: CGFloat = 1

    /// Переносит `path` в `net`, отбрасывая вершины ближе `minStep` к
    /// предыдущей оставленной. Начало и конец каждой линии остаются всегда:
    /// иначе короткая поездка на масштабе страны исчезла бы целиком, а не
    /// стала точкой.
    ///
    /// И ШЬЁТ: прогон, который начинается там же, где кончился прошлый (на
    /// экране ближе шага), продолжает ту же линию, а не открывает новую, —
    /// в том числе через границу двух вызовов, то есть двух бакетов индекса.
    /// Каждая отдельная линия — это ещё пара круглых концов на кадр.
    static func appendThinned(
        _ path: CGPath, to net: CGMutablePath,
        transform: CGAffineTransform, minStep: CGFloat
    ) {
        let limit = minStep * minStep
        var last = net.isEmpty ? CGPoint.zero : net.currentPoint
        var pending: CGPoint?
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint:
                if let p = pending { net.addLine(to: p); last = p; pending = nil }
                let start = e.points[0].applying(transform)
                let dx = start.x - last.x, dy = start.y - last.y
                if net.isEmpty || dx * dx + dy * dy >= limit {
                    net.move(to: start)
                    last = start
                }
            case .addLineToPoint:
                let p = e.points[0].applying(transform)
                let dx = p.x - last.x, dy = p.y - last.y
                if dx * dx + dy * dy >= limit {
                    net.addLine(to: p)
                    last = p
                    pending = nil
                } else {
                    pending = p
                }
            default:
                // Сеть собирается только из `move`/`addLine`
                // (`MapPathChunks.bucket`); остальное не переносится.
                if let p = pending { net.addLine(to: p); last = p; pending = nil }
            }
        }
        if let p = pending { net.addLine(to: p) }
    }
}

/// Слой жилки — тонкий контейнер над полосами растра.
///
/// `zPosition`, а не порядок вставки: полосы растра приезжают по одной и
/// каждая ложится сверху, а жилка обязана остаться выше них всех.
/// `masksToBounds` — потому что за краем растра лежит ровный туман без
/// коридоров, и линия, вылезшая туда, висела бы в пустоте.
final class VeinLayer: CALayer {
    private var shapes: [CAShapeLayer] = []

    override init() {
        super.init()
        actions = ["position": NSNull(), "bounds": NSNull(), "sublayers": NSNull()]
        zPosition = 1
        masksToBounds = true
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    /// Сколько проходов сейчас нарисовано — для теста.
    var strokeCount: Int { shapes.filter { !$0.isHidden && $0.path != nil }.count }

    /// Ставит проходы. Слои переиспользуются: ореол, белая подложка светлой
    /// палитры, сердцевина, обводка выбранного и сам выбранный.
    func apply(_ strokes: [FogVeilVein.Stroke], bounds: CGRect, scale: CGFloat) {
        frame = bounds
        while shapes.count < strokes.count {
            let shape = CAShapeLayer()
            shape.actions = [
                "path": NSNull(), "position": NSNull(), "bounds": NSNull(),
                "strokeColor": NSNull(), "lineWidth": NSNull(), "hidden": NSNull(),
            ]
            shape.fillColor = nil
            shape.lineCap = .round
            shape.lineJoin = .round
            addSublayer(shape)
            shapes.append(shape)
        }
        for (i, shape) in shapes.enumerated() {
            guard i < strokes.count else {
                shape.isHidden = true
                shape.path = nil
                continue
            }
            let stroke = strokes[i]
            shape.isHidden = false
            shape.frame = CGRect(origin: .zero, size: bounds.size)
            shape.contentsScale = scale
            shape.lineWidth = stroke.width
            shape.strokeColor = stroke.color.cgColor
            shape.path = stroke.path
        }
    }
}
