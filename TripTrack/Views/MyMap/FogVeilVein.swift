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
        chunks: MapPathChunks?, selected: [MKMapPoint]
    ) -> [Stroke] {
        guard rect.width > 0, rect.height > 0, sizePoints.width > 0 else { return [] }
        // Масштаб растра: точек экрана на точку карты. Он же `zoomScale` —
        // ровно тот, которым меряет ширины плиточный рендерер, поэтому
        // экранные ширины в координатах растра берутся как есть.
        let zoomScale = MKZoomScale(sizePoints.width / CGFloat(rect.width))
        let lod = FogVeilRenderer.lod(for: zoomScale)
        // Сдвиг к левому верхнему углу растра, затем масштаб: `p' = (p − o)·z`.
        let transform = CGAffineTransform(scaleX: CGFloat(zoomScale), y: CGFloat(zoomScale))
            .translatedBy(x: CGFloat(-rect.minX), y: CGFloat(-rect.minY))
        var out: [Stroke] = []

        if let chunks {
            let widest = max(RouteVeinRenderer.width(for: lod),
                             RouteVeinRenderer.halo(for: lod)?.width ?? 0) / CGFloat(zoomScale)
            let paths = chunks.visiblePaths(
                in: rect.insetBy(dx: -Double(widest) - 1, dy: -Double(widest) - 1),
                zoomScale: zoomScale)
            if !paths.isEmpty {
                let net = CGMutablePath()
                for path in paths { net.addPath(path, transform: transform) }
                // Ореол — первым: сердцевина ложится поверх него.
                if let halo = RouteVeinRenderer.halo(for: lod) {
                    let metre = MKMapPointsPerMeterAtLatitude(
                        MKMapPoint(x: rect.midX, y: rect.midY).coordinate.latitude)
                    let ceiling = FogVeilRenderer.corridorWidth(zoomScale: zoomScale, metre: metre)
                        * 1.2 * CGFloat(zoomScale)
                    out.append(Stroke(
                        path: net, width: min(halo.width, ceiling),
                        color: RouteVeinRenderer.veinColor.withAlphaComponent(halo.alpha)))
                }
                out.append(Stroke(
                    path: net, width: RouteVeinRenderer.width(for: lod),
                    color: RouteVeinRenderer.veinColor.withAlphaComponent(0.9)))
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
                    color: RouteVeinRenderer.casingColor))
                out.append(Stroke(
                    path: line, width: RouteVeinRenderer.selectedWidth,
                    color: RouteVeinRenderer.selectedColor))
            }
        }
        return out
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

    /// Ставит проходы. Слои переиспользуются: их не больше четырёх (ореол,
    /// сердцевина, обводка выбранного, сам выбранный).
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
