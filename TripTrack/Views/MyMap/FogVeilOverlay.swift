import MapKit

// MARK: - Индекс путей

/// Прогоны, разложенные по двум сеткам бакетов, у каждого бакета — один
/// готовый `CGPath`.
///
/// MapKit просит рендерер нарисовать ОДИН тайл за раз. Без индекса каждый тайл
/// обводит всю страну — именно это дёргало карту на панораме, и тем сильнее,
/// чем больше человек наездил.
///
/// Уровней два, и это не оптимизация «на всякий случай». Один бакет в 78 км
/// значит, что в тайл шириной 2 км приезжает `CGPath` со всей сетью города — и
/// обводится он восемь раз подряд. Второй уровень, 4.8 км, снимает с такого
/// тайла 90–95 % чужой геометрии. На дальнем зуме всё наоборот: там тайл сам
/// шире мелкого бакета, и перебирать тысячи мелких прямоугольников дороже, чем
/// отдать десяток крупных.
struct MapPathChunks {
    private struct Chunk {
        let rect: MKMapRect
        let path: CGPath
    }

    /// Выше этого зума считаем по мелкой сетке. Порог выбран так, чтобы тайл в
    /// 256 точек был примерно с десяток мелких бакетов: мельче — экономия
    /// сходит на нет, крупнее — перебор бакетов начинает стоить дороже самой
    /// отрисовки.
    static let fineZoom: MKZoomScale = 5e-4

    /// ~78 км на бакет: достаточно широко, чтобы плечо трассы осталось целым,
    /// достаточно тесно, чтобы городской тайл пропустил остальную карту.
    private static let coarseBucket = MKMapSize.world.width / 512
    /// ~4.8 км — размер, на котором улица перестаёт таскать за собой город.
    private static let fineBucket = MKMapSize.world.width / 8_192
    /// Штрих бывает много шире своей геометрии, поэтому бакет, чья линия чуть
    /// за краем тайла, всё равно может в него нарисовать. Основной запас
    /// добавляет рендерер (он один знает ширину коридора на этом зуме); здесь
    /// — только на округление.
    private static let coarsePadding: Double = 8_000
    private static let finePadding: Double = 2_000

    private let coarse: [Chunk]
    private let fine: [Chunk]

    init(_ polylines: [MKPolyline], transform: (MKMapPoint) -> CGPoint) {
        coarse = Self.bucket(polylines, size: Self.coarseBucket,
                             padding: Self.coarsePadding, transform: transform)
        fine = Self.bucket(polylines, size: Self.fineBucket,
                           padding: Self.finePadding, transform: transform)
    }

    private static func bucket(
        _ polylines: [MKPolyline], size: Double, padding: Double,
        transform: (MKMapPoint) -> CGPoint
    ) -> [Chunk] {
        var byBucket: [Int64: (rect: MKMapRect, path: CGMutablePath)] = [:]
        for line in polylines {
            guard line.pointCount >= 2 else { continue }
            let box = line.boundingMapRect
            let key = Int64(box.midX / size) &* 1_048_576 &+ Int64(box.midY / size)

            var entry = byBucket[key] ?? (box, CGMutablePath())
            entry.rect = entry.rect.union(box)
            let points = line.points()
            entry.path.move(to: transform(points[0]))
            for i in 1..<line.pointCount {
                entry.path.addLine(to: transform(points[i]))
            }
            byBucket[key] = entry
        }
        return byBucket.values.map {
            Chunk(rect: $0.rect.insetBy(dx: -padding, dy: -padding), path: $0.path)
        }
    }

    /// Пути, задевающие `rect`. Спрашивать ОДИН раз на тайл и переиспользовать
    /// во всех проходах пера: вуаль обводит их до четырнадцати раз, и заново
    /// перебирать бакеты на каждый проход — это четырнадцать перечислений ради
    /// одного ответа.
    func visiblePaths(in rect: MKMapRect, zoomScale: MKZoomScale) -> [CGPath] {
        let chunks = zoomScale >= Self.fineZoom ? fine : coarse
        return chunks.compactMap { $0.rect.intersects(rect) ? $0.path : nil }
    }
}

// MARK: - Кисть

/// Заливка вуали и прожигание коридоров — чистой функцией, без `MKOverlayRenderer`.
///
/// Вынесено не ради красоты: `MKMapSnapshotter` НЕ рисует оверлеи, и постер
/// «Поделиться» собирает карту сам, проецируя геометрию через
/// `snapshot.point(for:)`. Пока туман живёт внутри рендерера, у постера нет
/// способа нарисовать тот же туман — и картинка, которой человек делится,
/// разъезжается с тем, что он видит на экране.
enum FogVeilPainter {
    /// Объёмная ночная дымка: два слоя одного цвета, не «чёрное» и не шум.
    ///
    /// Верх и низ держатся близко к тёмной подложке Apple нарочно. При
    /// панораме MapKit довозит свои плитки позже нашего оверлея, и на ведущем
    /// крае видна полоса уже нарисованной карты (прототип 15 сен: одна заливка
    /// даёт ту же вспышку, значит это не цена нашей отрисовки, а лаг конвейера
    /// MapKit, и рендерером он не чинится). Единственное, что уменьшает ущерб,
    /// — низкий контраст между картой и вуалью.
    static let veilColorTop = UIColor(red: 0x0c/255, green: 0x0d/255, blue: 0x12/255, alpha: 1)
    static let veilColorBottom = UIColor(red: 0x1b/255, green: 0x1d/255, blue: 0x26/255, alpha: 1)
    /// Непрозрачна ВСЕГДА и на всех масштабах. До 0.7.0 здесь стояло 0.70, и
    /// тридцать процентов карты Apple было видно всегда — это затемнение, а не
    /// сокрытие.
    static let veilAlpha: CGFloat = 1.0
    /// Пятно дымки — чуть светлее и чуть синее заливки.
    static let hazeColor = UIColor(red: 0x2b/255, green: 0x31/255, blue: 0x42/255, alpha: 1)

    /// Как ложится объём на этот кусок мира.
    ///
    /// `top`/`bottom` — положение на рампе `veilColorTop → veilColorBottom` у
    /// верхнего и нижнего края куска (0…1). Считает их тот, кто знает мировые
    /// координаты, — иначе у каждого тайла свой градиент и стык тайлов виден
    /// сеткой. `haze` — альфа радиального пятна в центре; к краю оно гаснет в
    /// ноль, поэтому соседние куски сходятся без шва при любой её величине.
    struct Depth {
        var top: CGFloat
        var bottom: CGFloat
        var haze: CGFloat

        /// Один кусок на всю картинку — постер, снапшот, тест.
        static let flat = Depth(top: 0, bottom: 1, haze: 0.05)
    }

    /// Растущая прорезь у машины — «туман выгорает по новому пути».
    struct Reveal {
        let centre: CGPoint
        let radius: CGFloat
    }

    /// Заливка + перья. Всё в координатах контекста; про карту не знает ничего.
    static func paint(
        context: CGContext,
        paths: [CGPath],
        corridorWidth: CGFloat,
        passes: Int,
        tileRect: CGRect,
        depth: Depth,
        reveal: Reveal? = nil
    ) {
        // Большинство тайлов не лежит рядом ни с одной своей дорогой: сплошная
        // вуаль и больше ничего. Заливать их напрямую — без слоя прозрачности
        // и без проходов пера — это то, что не даёт широкому виду приезжать по
        // тайлу за раз. Вуаль накрывает весь мир, так что этим путём идёт
        // большинство тайлов.
        guard !paths.isEmpty || reveal != nil else {
            fill(context: context, rect: tileRect, depth: depth)
            return
        }

        // Дыры прожигаются `.destinationOut`, а он стирает всё, что уже лежит в
        // контексте, — поэтому вуаль получает свой слой прозрачности и не
        // дотягивается до оверлеев, нарисованных раньше. Аллокация этого буфера
        // и есть дорогая часть, и платят за неё только тайлы, которым дыры
        // действительно нужны.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        fill(context: context, rect: tileRect, depth: depth)

        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setBlendMode(.destinationOut)
        if !paths.isEmpty {
            for pass in FogVeilRenderer.feather(passes: passes) {
                context.beginPath()
                paths.forEach(context.addPath)
                context.setLineWidth(corridorWidth * pass.width)
                context.setStrokeColor(UIColor(white: 0, alpha: pass.alpha).cgColor)
                context.strokePath()
            }
        }
        if let reveal, reveal.radius > 0 {
            punch(context: context, reveal: reveal)
        }
        context.setBlendMode(.normal)
        context.endTransparencyLayer()
    }

    // MARK: Внутри

    private static func fill(context: CGContext, rect: CGRect, depth: Depth) {
        let space = CGColorSpaceCreateDeviceRGB()
        let colours = [ramp(depth.top).cgColor, ramp(depth.bottom).cgColor] as CFArray

        context.saveGState()
        context.clip(to: rect)
        if let gradient = CGGradient(colorsSpace: space, colors: colours, locations: [0, 1]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.midX, y: rect.minY),
                end: CGPoint(x: rect.midX, y: rect.maxY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        } else {
            context.setFillColor(ramp(0.5).cgColor)
            context.fill(rect)
        }

        // Пятно дымки. Гаснет в ноль на середине стороны тайла, поэтому какой
        // бы ни была его сила, соседний тайл подхватывает ровно нулём.
        if depth.haze > 0 {
            let radius = min(rect.width, rect.height) / 2
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            let stops = [
                hazeColor.withAlphaComponent(depth.haze).cgColor,
                hazeColor.withAlphaComponent(0).cgColor,
            ] as CFArray
            if let glow = CGGradient(colorsSpace: space, colors: stops, locations: [0, 1]) {
                context.drawRadialGradient(
                    glow, startCenter: centre, startRadius: 0,
                    endCenter: centre, endRadius: radius, options: []
                )
            }
        }
        context.restoreGState()
    }

    /// Круглая прорезь с мягким краем — тем же приёмом, что и коридор.
    private static func punch(context: CGContext, reveal: Reveal) {
        let space = CGColorSpaceCreateDeviceRGB()
        let stops = [
            UIColor(white: 0, alpha: 1).cgColor,
            UIColor(white: 0, alpha: 1).cgColor,
            UIColor(white: 0, alpha: 0).cgColor,
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: space, colors: stops, locations: [0, 0.55, 1]
        ) else { return }
        context.drawRadialGradient(
            gradient, startCenter: reveal.centre, startRadius: 0,
            endCenter: reveal.centre, endRadius: reveal.radius, options: []
        )
    }

    private static func ramp(_ t: CGFloat) -> UIColor {
        let k = min(1, max(0, t))
        var r0: CGFloat = 0, g0: CGFloat = 0, b0: CGFloat = 0, a0: CGFloat = 0
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        veilColorTop.getRed(&r0, green: &g0, blue: &b0, alpha: &a0)
        veilColorBottom.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        return UIColor(
            red: r0 + (r1 - r0) * k, green: g0 + (g1 - g0) * k,
            blue: b0 + (b1 - b0) * k, alpha: veilAlpha
        )
    }
}

// MARK: - Оверлей

/// Тьма над всем, где ты не был. Свои дороги прожигают в ней коридор с мягким
/// краем — карта читается как то, что ты открыл, а не как то, что тебе выдали.
///
/// Накрывает весь мир нарочно: угол без вуали читался бы как открытый.
final class FogVeilOverlay: NSObject, MKOverlay {
    let layer: RevealedLayer
    /// Растущая прорезь у машины на экране записи. `nil` у Атласа.
    ///
    /// `var`: прорезь растёт ШЕСТЬДЕСЯТ раз в секунду, и подменять ради этого
    /// сам оверлей значило бы шестьдесят раз в секунду пересобирать индекс
    /// путей всего открытого мира. Меняется только эта величина, а рендерер
    /// перерисовывает коробку вокруг точки (`FogRevealAnimation.rect`).
    var revealAround: RevealPoint?
    let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    var boundingMapRect: MKMapRect { .world }

    /// Где и насколько раскрыт туман прямо сейчас.
    struct RevealPoint {
        let coordinate: CLLocationCoordinate2D
        /// 0…1. Радиус прорези — доля от `FogVeilRenderer.revealMetres`.
        var progress: Double
    }

    init(layer: RevealedLayer, revealAround: RevealPoint? = nil) {
        self.layer = layer
        self.revealAround = revealAround
        super.init()
    }
}

// MARK: - Рендерер

final class FogVeilRenderer: MKOverlayRenderer {
    private let veil: FogVeilOverlay
    /// `var` и не `let` нарочно: пути собираются ПОСЛЕ `super.init` (раньше у
    /// `point(for:)` нет трансформа), а трогать `self` до инициализации всех
    /// полей нельзя.
    private var chunks: [RevealedLayer.LOD: MapPathChunks] = [:]

    /// Сколько раз собирался индекс путей. Ровно `LOD.allCases.count`, и
    /// вырасти он не имеет права: прорезь на экране записи растёт шестьдесят
    /// раз в секунду, и если ради неё подменять оверлей, каждый кадр будет
    /// пересобирать пути всего открытого мира. Держит `FogVeilTemporalTests`.
    private(set) var chunkBuilds = 0

    /// Полуширина коридора на улице, в метрах.
    ///
    /// Измерено прототипом 15 сентября на настоящей сетке улиц, а не на глаз:
    /// при ±75 м между двумя проеханными улицами в 195 м остаётся перемычка
    /// тумана в 45 м, при ±100 м они сливаются в одно пятно и квартал выходит
    /// открытым целиком. ±50 м — единственная из трёх, где между своими
    /// улицами остаётся видимая темнота, а сам коридор (25 экранных точек)
    /// заметно шире жилки. До 0.7.0 здесь стояло ±70 м, а до того ±120 м, и
    /// про те последние в коде было записано: «весь город выходил открытым, и
    /// туман выглядел так, будто его нет».
    static let streetHalfWidthMetres: Double = 50

    /// Пол ширины коридора в ЭКРАННЫХ точках — он же правило масштабирования:
    /// на улице побеждают метры, с региона и дальше пол.
    ///
    /// Прототип: на восьми точках (так было до 0.7.0) от прочищенной полосы
    /// после пера остаётся около 3 точек на сторону от жилки, и под
    /// непрозрачной вуалью это читается как линия, нарисованная по чёрному, а
    /// не как дыра в темноте. Двенадцать — жилка 2 pt плюс по ~5 pt
    /// прочищенного с каждой стороны; ниже падать нельзя.
    static let minVeinPoints: CGFloat = 12

    /// Радиус прорези у машины при `progress == 1`.
    static let revealMetres: Double = 150

    /// Шире этого на экране восьми ступеней пера мало: на полупрозрачной вуали
    /// террасы съедала сама прозрачность, на альфе 1.0 их видно.
    static let wideCorridorPoints: CGFloat = 60

    init(veil: FogVeilOverlay) {
        self.veil = veil
        super.init(overlay: veil)
        // Трансформ `point(for:)` появляется только после `super.init` и не
        // меняется всю жизнь рендерера — поэтому пути собираются здесь, один
        // раз, а не внутри каждого тайлового колбэка.
        for lod in RevealedLayer.LOD.allCases {
            chunks[lod] = MapPathChunks(veil.layer.polylines(for: lod)) { self.point(for: $0) }
            chunkBuilds += 1
        }
    }

    // MARK: Чистые функции

    /// Уровень детали по зуму. Коридор на масштабе страны — вена шириной в
    /// пиксель: рисовать её по точкам через 75 м значит платить за каждую
    /// сотню километров тысячей вершин, которых никто не увидит.
    static func lod(for zoomScale: MKZoomScale) -> RevealedLayer.LOD {
        if zoomScale > 1.5e-3 { return .fine }
        if zoomScale > 1.5e-4 { return .mid }
        return .far
    }

    /// Ширина коридора в координатах рендерера.
    static func corridorWidth(zoomScale: MKZoomScale, metre: Double) -> CGFloat {
        max(CGFloat(streetHalfWidthMetres * 2 * metre), minVeinPoints / zoomScale)
    }

    static func passes(forScreenWidth width: CGFloat) -> Int {
        width > wideCorridorPoints ? 14 : 8
    }

    /// От самого широкого и бледного к самому узкому и плотному:
    /// `.destinationOut` превращает жёсткий штрих в перьевую дыру.
    ///
    /// Каждый проход умножает то, что оставил предыдущий, поэтому альфы
    /// ВЫВЕДЕНЫ из кривой, по которой обязан идти край, а не подобраны руками:
    /// четыре подобранные ступени рисовали вокруг каждой дороги видимые
    /// террасы, как на топографической карте. По той же причине проходы нельзя
    /// прореживать: убери последний — и середина коридора никогда не очистится.
    static func feather(passes: Int) -> [(width: CGFloat, alpha: CGFloat)] {
        var out: [(CGFloat, CGFloat)] = []
        var remaining: CGFloat = 1
        for step in 0..<passes {
            let t = CGFloat(step + 1) / CGFloat(passes)
            let width = 1 - 0.82 * CGFloat(step) / CGFloat(max(passes - 1, 1))
            // Сколько вуали ещё стоит внутри этого радиуса: 1 на внешнем краю,
            // 0 в сердцевине.
            let target = pow(1 - t, 1.7)
            let alpha = remaining > 0 ? min(1, max(0, 1 - target / remaining)) : 1
            remaining = target
            out.append((width, alpha))
        }
        return out
    }

    /// Объём — от МИРОВОЙ координаты тайла, а не от его собственной.
    ///
    /// Волна длиной в шесть тайлов: у соседей общий край даёт одно и то же
    /// значение, поэтому стыка не видно, а на экране всё равно видно, что
    /// дымка не плоская. Длина волны привязана к размеру тайла, а не к миру,
    /// иначе на масштабе улицы весь экран был бы одного цвета.
    static func depth(for mapRect: MKMapRect) -> FogVeilPainter.Depth {
        let wave = mapRect.height * 6
        guard wave > 0 else { return .flat }
        func shade(_ y: Double) -> CGFloat {
            CGFloat(0.5 + 0.5 * sin(2 * Double.pi * y / wave))
        }
        return FogVeilPainter.Depth(
            top: shade(mapRect.minY),
            bottom: shade(mapRect.maxY),
            haze: 0.06 * hazeAmplitude(for: mapRect)
        )
    }

    /// Сила пятна — от координат тайла, чтобы при перерисовке того же тайла она
    /// не менялась (мигание) и чтобы пятна не выстроились правильной сеткой.
    private static func hazeAmplitude(for mapRect: MKMapRect) -> CGFloat {
        let col = Int64((mapRect.midX / mapRect.width).rounded(.down))
        let row = Int64((mapRect.midY / mapRect.height).rounded(.down))
        var hash = UInt64(bitPattern: col &* 73_856_093 ^ row &* 19_349_663)
        hash ^= hash >> 33
        hash = hash &* 0xff51_afd7_ed55_8ccd
        hash ^= hash >> 29
        return 0.4 + 0.6 * CGFloat(hash % 1_000) / 1_000
    }

    // MARK: Отрисовка

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let tile = rect(for: mapRect)
        // Метров на точку карты зависит от широты, поэтому берётся у ЭТОГО
        // тайла, а не у середины сети: иначе коридор в Мурманске нарисован по
        // мерке Сочи.
        let metre = MKMapPointsPerMeterAtLatitude(
            MKMapPoint(x: mapRect.midX, y: mapRect.midY).coordinate.latitude)
        let width = Self.corridorWidth(zoomScale: zoomScale, metre: metre)

        // Запрос расширяется на половину штриха: бакет, чья линия лежит за
        // краем тайла, всё равно рисует в него — на дальнем зуме коридор шире
        // километра.
        let reach = Double(width) / 2 + 1
        let query = mapRect.insetBy(dx: -reach, dy: -reach)
        let paths = chunks[Self.lod(for: zoomScale)]?
            .visiblePaths(in: query, zoomScale: zoomScale) ?? []

        FogVeilPainter.paint(
            context: context,
            paths: paths,
            corridorWidth: width,
            passes: Self.passes(forScreenWidth: width * zoomScale),
            tileRect: tile,
            depth: Self.depth(for: mapRect),
            reveal: reveal(in: mapRect, zoomScale: zoomScale, metre: metre)
        )
    }

    private func reveal(
        in mapRect: MKMapRect, zoomScale: MKZoomScale, metre: Double
    ) -> FogVeilPainter.Reveal? {
        guard let point = veil.revealAround, point.progress > 0 else { return nil }
        let centre = MKMapPoint(point.coordinate)
        let radius = max(
            CGFloat(Self.revealMetres * point.progress * metre),
            Self.minVeinPoints / zoomScale
        )
        let box = MKMapRect(
            x: centre.x - Double(radius), y: centre.y - Double(radius),
            width: Double(radius) * 2, height: Double(radius) * 2
        )
        guard box.intersects(mapRect) else { return nil }
        return FogVeilPainter.Reveal(centre: self.point(for: centre), radius: radius)
    }
}
