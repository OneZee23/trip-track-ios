import MapKit

/// Одна тёплая линия по оси коридора — маршрут внутри прочищенного.
///
/// Это ВСЯ дорожная графика Атласа после 0.7.0. До неё здесь лежал хитмап по
/// модели Strava: шесть тепловых полос `RoadHeatRamp`, ореол у «горячих» дорог
/// шириной втрое больше самой линии, и поверх всего второй, ещё более яркий
/// след выбранной поездки градиентом скорости. Пока такая лента лежит в центре
/// кадра, картинка остаётся хитмапом, даже если вуаль сделать непрозрачной, —
/// потому что глаз читает «линия есть, дырки нет».
///
/// Жилка не говорит, сколько раз ты здесь ездил. Она говорит только «здесь
/// дорога», и этого достаточно: сколько раз — отвечает экран места.
final class RouteVeinOverlay: NSObject, MKOverlay {
    enum Style {
        /// Вся открытая сеть.
        case network
        /// Одна выбранная поездка — та же жилка, только шире.
        case selected
    }

    let style: Style
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect

    private let levels: [RevealedLayer.LOD: [MKPolyline]]

    func polylines(for lod: RevealedLayer.LOD) -> [MKPolyline] { levels[lod] ?? [] }

    /// Сеть — из того же слоя, что и вуаль. Один источник на дыру и на линию в
    /// ней: разъехаться им нельзя, иначе жилка окажется рядом с коридором.
    init(layer: RevealedLayer) {
        style = .network
        var built: [RevealedLayer.LOD: [MKPolyline]] = [:]
        var box = MKMapRect.null
        for lod in RevealedLayer.LOD.allCases {
            let lines = layer.polylines(for: lod)
            built[lod] = lines
            if lod == .fine {
                for line in lines {
                    box = box.isNull ? line.boundingMapRect : box.union(line.boundingMapRect)
                }
            }
        }
        levels = built
        boundingMapRect = box.isNull ? .world : box
        coordinate = MKMapPoint(x: box.isNull ? 0 : box.midX, y: box.isNull ? 0 : box.midY).coordinate
        super.init()
    }

    /// Выбранная поездка. Уровней детали у неё нет: это одна превью-полилиния
    /// на несколько сотен вершин, прореживать там нечего.
    init?(route: [CLLocationCoordinate2D]) {
        guard route.count > 1 else { return nil }
        style = .selected
        let line = MKPolyline(coordinates: route, count: route.count)
        levels = Dictionary(uniqueKeysWithValues: RevealedLayer.LOD.allCases.map { ($0, [line]) })
        boundingMapRect = line.boundingMapRect
        coordinate = MKMapPoint(x: line.boundingMapRect.midX, y: line.boundingMapRect.midY).coordinate
        super.init()
    }
}

final class RouteVeinRenderer: MKOverlayRenderer {
    private let vein: RouteVeinOverlay
    private var chunks: [RevealedLayer.LOD: MapPathChunks] = [:]

    /// Тёплый янтарь из эталонных кадров владельца. Не акцент бренда: жилка —
    /// это свет внутри тумана, а не элемент интерфейса.
    static let veinColor = UIColor(red: 0xf0/255, green: 0xa0/255, blue: 0x70/255, alpha: 1)
    /// Выбранная поездка — тот же цвет, светлее и плотнее.
    static let selectedColor = UIColor(red: 0xf6/255, green: 0xb9/255, blue: 0x8a/255, alpha: 1)
    /// Тёмная обводка: без неё выбранная линия сливается с прочищенным
    /// коридором, в котором лежит.
    static let casingColor = UIColor(red: 0x14/255, green: 0x14/255, blue: 0x1a/255, alpha: 0.55)

    static let selectedWidth: CGFloat = 3.2
    static let casingExtra: CGFloat = 2.0

    init(vein: RouteVeinOverlay) {
        self.vein = vein
        super.init(overlay: vein)
        for lod in RevealedLayer.LOD.allCases {
            chunks[lod] = MapPathChunks(vein.polylines(for: lod)) { self.point(for: $0) }
        }
    }

    /// Ширина жилки в экранных точках. Вблизи чуть толще, издали тоньше —
    /// иначе на масштабе страны сеть сливается в пятно, а на улице линия
    /// выглядит царапиной.
    static func width(for lod: RevealedLayer.LOD) -> CGFloat {
        switch lod {
        case .fine: return 2.2
        case .mid:  return 2.0
        case .far:  return 1.6
        }
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let lod = FogVeilRenderer.lod(for: zoomScale)
        let screenWidth = vein.style == .selected ? Self.selectedWidth : Self.width(for: lod)
        let width = screenWidth / zoomScale
        let reach = Double(width) + 1
        let paths = chunks[lod]?
            .visiblePaths(in: mapRect.insetBy(dx: -reach, dy: -reach), zoomScale: zoomScale) ?? []
        guard !paths.isEmpty else { return }

        context.setLineCap(.round)
        context.setLineJoin(.round)

        if vein.style == .selected {
            context.beginPath()
            paths.forEach(context.addPath)
            context.setLineWidth(width + Self.casingExtra / zoomScale)
            context.setStrokeColor(Self.casingColor.cgColor)
            context.strokePath()
        }

        context.beginPath()
        paths.forEach(context.addPath)
        context.setLineWidth(width)
        context.setStrokeColor(
            vein.style == .selected
                ? Self.selectedColor.cgColor
                : Self.veinColor.withAlphaComponent(0.9).cgColor
        )
        context.strokePath()
    }
}
