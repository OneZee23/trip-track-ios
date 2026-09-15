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
    /// Тот же индекс, что у вуали, и по той же причине: `init` рендерера —
    /// главный поток в момент первого показа карты.
    private let index = MapPathIndex()

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

    /// Ширина ореола и его альфа на этом уровне детали, в ЭКРАННЫХ точках.
    ///
    /// На стране жилка в 1.6 pt — волосок: до 0.7.0 рядом с ней лежал хитмап и
    /// «горячий» ореол втрое шире линии, а теперь на весь кадр остаётся одна
    /// нитка, и спека обещает светящуюся вену, а не царапину. Ореол — первый,
    /// самый широкий и самый бледный проход тем же янтарём.
    ///
    /// Потолок ширины — `FogVeilRenderer.corridorWidth × 1.2`: шире, и янтарь
    /// ляжет на вуаль сплошняком вместо того, чтобы светиться внутри
    /// прочищенного коридора. На `.fine` ореола нет вовсе — там свет даёт сам
    /// коридор, а второй светящийся след вернул бы «страва-ленту».
    static func halo(for lod: RevealedLayer.LOD) -> (width: CGFloat, alpha: CGFloat)? {
        switch lod {
        case .fine: return nil
        case .mid:  return (8, 0.10)
        case .far:  return (10, 0.14)
        }
    }

    init(vein: RouteVeinOverlay) {
        self.vein = vein
        super.init(overlay: vein)
        // Индекс — вне главного потока, как у вуали; `point(for:)` при этом
        // зовётся с фоновой очереди, и это законно: MapKit сам зовёт
        // `draw(_:zoomScale:in:)` параллельно на своих потоках, а система
        // координат рендерера выведена из `boundingMapRect` и зафиксирована с
        // `super.init` (подробнее — в `FogVeilRenderer.init`).
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.index.prepare(
                source: { vein.polylines(for: $0) },
                transform: { self.point(for: $0) }
            )
            DispatchQueue.main.async { self.setNeedsDisplay() }
        }
    }

    /// Сколько наборов бакетов собрано — для тех же тестов, что у вуали.
    var chunkBuilds: Int { index.builds }

    /// Ширина сердцевины жилки в экранных точках.
    ///
    /// Издали ТОЛЩЕ, а не тоньше, — и это правка по кадрам 15 сентября. Раньше
    /// на стране стояло 1.6 pt из соображения «сеть сольётся в пятно», но
    /// сливаться там давно нечему: хитмапа рядом нет, и на весь кадр остаётся
    /// одна нитка в волос. Коридор на стране тоже уходит на свой экранный пол
    /// (12 pt), так что 3 pt внутри него — по-прежнему линия внутри
    /// прочищенного, а не заливка.
    static func width(for lod: RevealedLayer.LOD) -> CGFloat {
        switch lod {
        case .fine: return 2.2
        case .mid:  return 2.8
        case .far:  return 3.0
        }
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let lod = FogVeilRenderer.lod(for: zoomScale)
        let screenWidth = vein.style == .selected ? Self.selectedWidth : Self.width(for: lod)
        let width = screenWidth / zoomScale
        // Запрос расширяется по САМОМУ широкому проходу: ореол вылезает за
        // сердцевину втрое, и бакет за краем тайла всё равно светит в него.
        let widest = max(screenWidth, Self.halo(for: lod)?.width ?? 0) / zoomScale
        let reach = Double(widest) + 1
        // Индекс ещё собирается — жилки просто нет: её отсутствие на долю
        // секунды честнее, чем ожидание на потоке отрисовки.
        guard let chunks = index.ready(for: lod) else { return }
        let paths = chunks
            .visiblePaths(in: mapRect.insetBy(dx: -reach, dy: -reach), zoomScale: zoomScale)
        guard !paths.isEmpty else { return }

        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Ореол — первым: сердцевина ложится поверх него, а не наоборот.
        if let halo = Self.halo(for: lod) {
            let metre = MKMapPointsPerMeterAtLatitude(
                MKMapPoint(x: mapRect.midX, y: mapRect.midY).coordinate.latitude)
            let ceiling = FogVeilRenderer.corridorWidth(zoomScale: zoomScale, metre: metre) * 1.2
            context.beginPath()
            paths.forEach(context.addPath)
            context.setLineWidth(min(halo.width / zoomScale, ceiling))
            context.setStrokeColor(Self.veinColor.withAlphaComponent(halo.alpha).cgColor)
            context.strokePath()
        }

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
