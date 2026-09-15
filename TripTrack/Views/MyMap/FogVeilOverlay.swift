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

    /// Какие наборы бакетов этому индексу вообще нужны.
    ///
    /// Уровень детали и уровень бакетов выбираются по ОДНОМУ и тому же зуму, и
    /// пороги у них разные: `.fine` живёт выше 1.5e-3, то есть всегда выше
    /// `fineZoom`, а `.far` — ниже 1.5e-4, то есть всегда ниже. Значит на
    /// `.fine` грубый набор недостижим НИКОГДА, а на `.far` — мелкий, и до
    /// 0.7.0 оба всё равно собирались: шесть наборов вместо четырёх, причём
    /// самый дорогой из мёртвых — грубые бакеты полноразрядной геометрии
    /// `.fine` (на зрелой библиотеке это десятки мегабайт `CGPath`).
    enum Levels {
        case fine, coarse, both

        var buildsFine: Bool { self != .coarse }
        var buildsCoarse: Bool { self != .fine }
    }

    /// Достижимые наборы для этого уровня детали.
    static func levels(for lod: RevealedLayer.LOD) -> Levels {
        switch lod {
        case .fine: return .fine
        case .mid:  return .both
        case .far:  return .coarse
        }
    }

    private let coarse: [Chunk]?
    private let fine: [Chunk]?

    /// Сколько наборов бакетов собрано — единица счёта для сторожа
    /// (`FogVeilRenderer.chunkBuilds`).
    var builtLevels: Int { (fine == nil ? 0 : 1) + (coarse == nil ? 0 : 1) }

    init(_ polylines: [MKPolyline], levels: Levels = .both, transform: (MKMapPoint) -> CGPoint) {
        coarse = levels.buildsCoarse
            ? Self.bucket(polylines, size: Self.coarseBucket,
                          padding: Self.coarsePadding, transform: transform)
            : nil
        fine = levels.buildsFine
            ? Self.bucket(polylines, size: Self.fineBucket,
                          padding: Self.finePadding, transform: transform)
            : nil
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
        // Если нужного набора нет, отдаём тот, что есть: спросить недостижимый
        // уровень — это ошибка в `levels(for:)`, но платить за неё пустой
        // картой (сеть исчезла, вуаль сплошная) нельзя.
        let chunks = (zoomScale >= Self.fineZoom ? fine ?? coarse : coarse ?? fine) ?? []
        return chunks.compactMap { $0.rect.intersects(rect) ? $0.path : nil }
    }
}

// MARK: - Индекс путей

/// Индекс путей, который собирается ОДИН раз и ВНЕ главного потока, а до
/// готовности честно говорит «меня ещё нет».
///
/// Собирать в `draw` нельзя: MapKit зовёт его на своих потоках отрисовки, и
/// тайл, которому не повезло прийти первым, ждал бы всю сеть целиком — а
/// остальные ждали бы его на замке. Собирать в `init` рендерера тоже нельзя:
/// `rendererFor` MapKit зовёт на ГЛАВНОМ потоке, перед первым кадром карты,
/// то есть ровно тогда, когда человек ждёт картинку.
///
/// Поэтому: `prepare` на фоновой очереди из `init`, а пока не готово — тайл
/// рисуется сплошной заливкой без коридоров. Это честный промежуточный кадр:
/// он не показывает карту Apple там, где её показывать нельзя.
///
/// `NSLock`, потому что читают его потоки отрисовки, а пишет фоновый.
final class MapPathIndex {
    private let lock = NSLock()
    private var built: [RevealedLayer.LOD: MapPathChunks] = [:]
    private var levelsBuilt = 0
    private var mainThreadBuild = false

    /// Собиралась ли хоть одна порция на ГЛАВНОМ потоке. Для теста: «ноль
    /// сборок сразу после `init`» проверяло не правило, а то, что фоновая
    /// очередь не успела, — и на маленьком слое это флейк, а не сторож.
    var builtOnMainThread: Bool {
        lock.lock(); defer { lock.unlock() }
        return mainThreadBuild
    }

    /// Сколько НАБОРОВ БАКЕТОВ собрано за жизнь индекса. Потолок — четыре
    /// (`.fine` мелкий, `.mid` оба, `.far` грубый), и вырасти он не имеет
    /// права: прорезь на экране записи растёт шестьдесят раз в секунду, и
    /// если ради неё подменять оверлей, каждый кадр пересобирал бы пути всего
    /// открытого мира. Держит `FogVeilTemporalTests`.
    var builds: Int {
        lock.lock(); defer { lock.unlock() }
        return levelsBuilt
    }

    /// Готовый индекс уровня — или `nil`, пока сборка не дошла до него.
    func ready(for lod: RevealedLayer.LOD) -> MapPathChunks? {
        lock.lock(); defer { lock.unlock() }
        return built[lod]
    }

    /// Собрать все достижимые наборы. Зовётся один раз и не с главного потока.
    /// Уровни складываются по одному: первый готовый начинает рисовать
    /// коридоры, не дожидаясь остальных.
    func prepare(
        source: (RevealedLayer.LOD) -> [MKPolyline],
        transform: @escaping (MKMapPoint) -> CGPoint
    ) {
        let onMain = Thread.isMainThread
        for lod in RevealedLayer.LOD.allCases {
            let chunks = MapPathChunks(
                source(lod), levels: MapPathChunks.levels(for: lod), transform: transform)
            lock.lock()
            if onMain { mainThreadBuild = true }
            built[lod] = chunks
            levelsBuilt += chunks.builtLevels
            lock.unlock()
        }
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
    /// сеткой. `haze` — поле пятен; `nil` значит «только рампа».
    struct Depth {
        var top: CGFloat
        var bottom: CGFloat
        var haze: Haze?

        /// Один кусок на всю картинку — постер, снапшот, тест. Дымку такой
        /// кусок задаёт сам: у него нет тайлов, от координат которых её сеять.
        static let flat = Depth(top: 0, bottom: 1, haze: nil)
    }

    /// Поле пятен дымки — то, что делает вуаль объёмной, а не покрашенной.
    ///
    /// До правки 15 сентября на тайл приходилось ОДНО пятно, всегда ровно в его
    /// центре: центр держал бесшовность (к краю пятно гасло в ноль), но он же
    /// и выстраивал узор правильной сеткой, а альфа в 2–4 уровня RGB делала его
    /// невидимым. Теперь бесшовность держит другое: пятна сеются на МИРОВОЙ
    /// сетке, и каждый кусок рисует не только свои пятна, но и пятна восьми
    /// соседних ячеек сеялки, обрезая их по себе. Пятно, севшее на стык, обе
    /// стороны рисуют одинаково — потому что считают его от одних и тех же
    /// мировых координат, а не от своих.
    struct Haze {
        /// Мировой прямоугольник рисуемого куска (координаты `MKMapRect`).
        var world: MKMapRect
        /// Шаг сеялки в тех же единицах. ФИКСИРОВАННЫЙ для уровня детали
        /// (`FogVeilRenderer.hazeCell(for:)`), а не производный от размера
        /// тайла: от размера тайла узор менялся бы целиком на каждом зуме.
        var cell: Double
    }

    /// Одно пятно: центр в мировых координатах, радиус там же, своя альфа.
    struct HazeBlob {
        var x: Double
        var y: Double
        var radius: Double
        var alpha: CGFloat
    }

    /// Сколько пятен сеется в ячейку.
    static let hazeBlobsPerCell = 2

    /// Потолок пятен на ОДИН тайл.
    ///
    /// Сеялка ходит по ячейкам, накрывающим тайл, то есть по
    /// `(ширина тайла / ячейка)²`. Ограничения зума у «Атласа» нет, и на
    /// выведенной в мир карте тайл шире дальней ячейки в восемьдесят раз —
    /// это пятнадцать тысяч градиентов на ОДИН тайл вместо десятка, за
    /// границей той полосы зумов, которую мерит `MapRenderCostTests`.
    ///
    /// Потолок ставится двумя правилами сразу: ячейка не мельче полутора
    /// тайлов (`hazeMinCellTiles` — на таком зуме пятна мельче всё равно
    /// субпиксельные) и жёсткий срез списка здесь. Второе — страховка на
    /// случай, если первое кто-то ослабит.
    static let hazeBlobsPerTile = 3

    /// Во сколько раз ячейка сеялки обязана быть крупнее рисуемого куска.
    /// Полтора: при меньшем в кусок попадает больше четырёх ячеек, и потолок
    /// начинает срезать пятна, которые сосед нарисует, — то есть шов.
    static let hazeMinCellTiles: Double = 1.6
    /// Альфа пятна. Ниже 6 % — те самые 2–4 уровня RGB, которых глаз не видит;
    /// выше 10 % — начинает спорить с верхней границей светлоты (см.
    /// `testPainterFillsAnEmptyTileOpaque`: полоса недогруженных плиток Apple
    /// на панораме становится видна).
    static let hazeAlphaRange: ClosedRange<CGFloat> = 0.06...0.10

    /// Ступени альфы, и их ровно три: три силы пятна читаются как объём, а
    /// непрерывная шкала на 4 % размаха — нет.
    static let hazeAlphaLevels: [CGFloat] = [0.06, 0.08, 0.10]
    /// Радиус пятна в долях ячейки. Растёт вместе с ячейкой, то есть на дальнем
    /// LOD пятна крупнее — там и тайл крупнее.
    ///
    /// Верхняя граница — не вкус, а бюджет тайла. Пятна закрывают примерно
    /// `2 × π × r²` площади ячейки, и платится она ПИКСЕЛЯМИ: чем рисовать
    /// (градиент, картинка, сплошные кольца) — почти не важно, все три
    /// упираются в пропускную способность памяти. Замер 15 сен на пустом
    /// тайле: 0.26 мс без дымки, +0.30 мс при 0.20…0.34 (тайл сравнялся с
    /// тем, в котором прожигается коридор, — а именно этого не должно быть
    /// никогда), +0.10 мс здесь. Сторож — `MapRenderCostTests
    /// .testVeilTilesWithNoRoadsAreFarCheaperThanTilesWithThem`.
    static let hazeRadiusRange: ClosedRange<Double> = 0.10...0.18

    /// Пятна, которые видит ЭТОТ кусок мира: свои и соседних ячеек, с клипом
    /// по куску и с потолком `hazeBlobsPerTile`.
    ///
    /// Чистая функция, потому что и цена, и бесшовность проверяются только
    /// счётом: «сколько пятен на мировом тайле» глазами не увидеть.
    static func hazeBlobs(in haze: Haze) -> [HazeBlob] {
        let world = haze.world
        guard haze.cell > 0, world.width > 0, world.height > 0 else { return [] }
        // Ячейка НЕ МЕЛЬЧЕ куска: иначе их в куске сотни, и каждая со своими
        // пятнами. Правило общее для всех тайлов одного зума (ширина тайла у
        // них одна), поэтому соседи по-прежнему считают пятна одинаково.
        let cell = max(haze.cell, world.width * hazeMinCellTiles)
        let reach = cell * hazeRadiusRange.upperBound
        let minCol = Int64(((world.minX - reach) / cell).rounded(.down))
        let maxCol = Int64(((world.maxX + reach) / cell).rounded(.down))
        let minRow = Int64(((world.minY - reach) / cell).rounded(.down))
        let maxRow = Int64(((world.maxY + reach) / cell).rounded(.down))
        guard maxCol >= minCol, maxRow >= minRow else { return [] }

        var out: [HazeBlob] = []
        for col in minCol...maxCol {
            for row in minRow...maxRow {
                for blob in hazeBlobs(col: col, row: row, cell: cell) {
                    // Пятно, не дотянувшееся до куска, стоит одного сравнения,
                    // а нарисованное — целого прохода градиента.
                    guard blob.x + blob.radius > world.minX, blob.x - blob.radius < world.maxX,
                          blob.y + blob.radius > world.minY, blob.y - blob.radius < world.maxY
                    else { continue }
                    out.append(blob)
                    if out.count == hazeBlobsPerTile { return out }
                }
            }
        }
        return out
    }

    /// Пятна одной ячейки сеялки — чистая функция от её координат.
    ///
    /// Детерминированность здесь не «приятное свойство», а условие
    /// бесшовности: два соседних тайла считают пятна общей ячейки каждый сам, и
    /// разойтись им нельзя ни при перерисовке, ни между запусками.
    static func hazeBlobs(col: Int64, row: Int64, cell: Double) -> [HazeBlob] {
        (0..<hazeBlobsPerCell).map { index in
            var seed = UInt64(bitPattern: col &* 73_856_093 ^ row &* 19_349_663
                                ^ Int64(index) &* 83_492_791)
            func next() -> Double {
                seed = seed &+ 0x9E37_79B9_7F4A_7C15
                var z = seed
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                z = z ^ (z >> 31)
                return Double(z % 1_000_000) / 1_000_000
            }
            let spread = hazeRadiusRange.upperBound - hazeRadiusRange.lowerBound
            return HazeBlob(
                x: (Double(col) + next()) * cell,
                y: (Double(row) + next()) * cell,
                radius: (hazeRadiusRange.lowerBound + spread * next()) * cell,
                alpha: hazeAlphaLevels[
                    min(hazeAlphaLevels.count - 1, Int(next() * Double(hazeAlphaLevels.count)))]
            )
        }
    }

    /// Растущая прорезь у машины — «туман выгорает по новому пути».
    struct Reveal {
        let centre: CGPoint
        let radius: CGFloat
    }

    /// Заливка + перья. Всё в координатах контекста; про карту не знает ничего.
    ///
    /// Это композиция двух половин ниже, и единственная причина, по которой она
    /// осталась отдельной функцией, — плиточный рендерер: у него кусок и слой
    /// прозрачности совпадают, потому что MapKit даёт ему ровно один тайл за
    /// раз. У экранной вуали (`FogVeilBitmap`) кусков десятки, а слой обязан
    /// быть ОДИН на всю картинку — иначе платятся двадцать четыре открытия
    /// буфера и триста проходов пера (замер 15 сен: полный кадр `.fine` 211 мс
    /// при 24 тайлах против 142 мс при 15 — цену держит число тайлов, а не
    /// число пикселей).
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
            fillAndHaze(context: context, tile: tileRect, depth: depth)
            return
        }

        // Дыры прожигаются `.destinationOut`, а он стирает всё, что уже лежит в
        // контексте, — поэтому вуаль получает свой слой прозрачности и не
        // дотягивается до оверлеев, нарисованных раньше. Аллокация этого буфера
        // и есть дорогая часть, и платят за неё только тайлы, которым дыры
        // действительно нужны.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        fillAndHaze(context: context, tile: tileRect, depth: depth)
        punch(context: context, corridors: paths, corridorWidth: corridorWidth,
              passes: passes, reveal: reveal)
        context.endTransparencyLayer()
    }

    /// Первая половина кисти: заливка и дымка ОДНОГО куска.
    ///
    /// Кусок здесь не «оптимизация по частям», а условие рисунка: и рампа
    /// глубины, и сеялка дымки привязаны к МИРОВЫМ координатам куска
    /// (`FogVeilRenderer.depth`), поэтому один прямоугольник на весь экран дал
    /// бы другую картинку, а не ту же быстрее. Слой прозрачности НЕ
    /// открывается: у заливки стирать нечего.
    static func fillAndHaze(context: CGContext, tile: CGRect, depth: Depth) {
        fill(context: context, rect: tile, depth: depth)
    }

    /// Вторая половина: коридоры и прорезь у машины, прожжённые в то, что уже
    /// лежит в контексте.
    ///
    /// Зовущий ОБЯЗАН быть внутри слоя прозрачности (`beginTransparencyLayer`):
    /// `.destinationOut` стирает всё, до чего дотянется, включая чужие оверлеи
    /// под вуалью. Функция про свой слой не знает нарочно — именно это
    /// позволяет экранной вуали открыть его ОДИН раз на весь растр, а
    /// плиточному рендереру — на каждый тайл.
    static func punch(
        context: CGContext,
        corridors: [CGPath],
        corridorWidth: CGFloat,
        passes: Int,
        reveal: Reveal? = nil
    ) {
        guard !corridors.isEmpty || reveal != nil else { return }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setBlendMode(.destinationOut)
        if !corridors.isEmpty {
            for pass in FogVeilRenderer.feather(passes: passes) {
                context.beginPath()
                corridors.forEach(context.addPath)
                context.setLineWidth(corridorWidth * pass.width)
                context.setStrokeColor(UIColor(white: 0, alpha: pass.alpha).cgColor)
                context.strokePath()
            }
        }
        if let reveal, reveal.radius > 0 {
            punchReveal(context: context, reveal: reveal)
        }
        context.setBlendMode(.normal)
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

        if let haze = depth.haze { paintHaze(context: context, rect: rect, haze: haze) }
        context.restoreGState()
    }

    /// Пятна этой ячейки и всех, что дотягиваются до куска.
    /// Градиент строится ОДИН на все пятна, а сила каждого приезжает через
    /// `setAlpha`: `CGGradient` на пятно — это сотня аллокаций на тайл ради
    /// одного числа.
    private static func paintHaze(context: CGContext, rect: CGRect, haze: Haze) {
        let world = haze.world
        let blobs = hazeBlobs(in: haze)
        guard !blobs.isEmpty, rect.width > 0, rect.height > 0,
              world.width > 0, world.height > 0 else { return }
        let stops = [
            hazeColor.withAlphaComponent(1).cgColor,
            hazeColor.withAlphaComponent(0).cgColor,
        ] as CFArray
        guard let glow = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: stops, locations: [0, 1]
        ) else { return }

        let sx = rect.width / CGFloat(world.width)
        let sy = rect.height / CGFloat(world.height)
        context.saveGState()
        context.clip(to: rect)
        for blob in blobs {
            let centre = CGPoint(
                x: rect.minX + CGFloat(blob.x - world.minX) * sx,
                y: rect.minY + CGFloat(blob.y - world.minY) * sy
            )
            context.setAlpha(blob.alpha)
            context.drawRadialGradient(
                glow, startCenter: centre, startRadius: 0,
                endCenter: centre, endRadius: CGFloat(blob.radius) * sx, options: []
            )
        }
        context.setAlpha(1)
        context.restoreGState()
    }

    /// Круглая прорезь с мягким краем — тем же приёмом, что и коридор.
    private static func punchReveal(context: CGContext, reveal: Reveal) {
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
    let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    var boundingMapRect: MKMapRect { .world }

    /// Где и насколько раскрыт туман прямо сейчас.
    ///
    /// Читается из `draw`, а его MapKit зовёт ОДНОВРЕМЕННО на нескольких
    /// фоновых потоках — по тайлу на поток. Пишется с главного, шестьдесят раз
    /// в секунду. Четыре `Double` и флаг опционала атомарно не записываются
    /// ничем: порванное чтение даёт прорезь не в том месте или радиус из
    /// чужого кадра, и заметить это можно только глазами на движущейся машине.
    /// Поэтому замок, а не `var` — тот же `NSLock`, что у `MapPathIndex`, и
    /// по той же причине.
    ///
    /// Точка меняется целиком, одним присваиванием: подменять ради неё сам
    /// оверлей значило бы шестьдесят раз в секунду пересобирать индекс путей
    /// всего открытого мира, а рендерер и так перерисовывает только коробку
    /// вокруг точки (`FogRevealAnimation.rect`).
    var revealAround: RevealPoint? {
        get {
            revealLock.lock()
            defer { revealLock.unlock() }
            return storedReveal
        }
        set {
            revealLock.lock()
            storedReveal = newValue
            revealLock.unlock()
        }
    }

    private let revealLock = NSLock()
    private var storedReveal: RevealPoint?

    /// Где и насколько раскрыт туман — ЦЕЛИКОМ, одним значением.
    struct RevealPoint {
        let coordinate: CLLocationCoordinate2D
        /// 0…1. Радиус прорези — доля от `FogVeilRenderer.revealMetres`.
        var progress: Double
    }

    init(layer: RevealedLayer, revealAround: RevealPoint? = nil) {
        self.layer = layer
        self.storedReveal = revealAround
        super.init()
    }
}

// MARK: - Рендерер

final class FogVeilRenderer: MKOverlayRenderer {
    private let veil: FogVeilOverlay
    private let index = MapPathIndex()

    /// Сколько наборов бакетов собрано. Потолок — четыре достижимых пары
    /// (уровень детали × уровень бакетов), и вырасти он не имеет права:
    /// прорезь на экране записи растёт шестьдесят раз в секунду, и если ради
    /// неё подменять оверлей, каждый кадр будет пересобирать пути всего
    /// открытого мира. Держит `FogVeilTemporalTests`.
    var chunkBuilds: Int { index.builds }

    /// Собирался ли индекс на главном потоке — сторож того же правила, только
    /// не зависящий от того, успела ли фоновая очередь (см. `MapPathIndex`).
    var indexBuiltOnMainThread: Bool { index.builtOnMainThread }

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
        // Трансформ `point(for:)` появляется только после `super.init` — и это
        // единственная причина, по которой сборка вообще привязана к
        // рендереру. Сам `init` зовёт `rendererFor` на ГЛАВНОМ потоке перед
        // первым кадром карты, поэтому пути собираются на фоновой очереди, а
        // до готовности тайл — сплошная заливка без коридоров.
        //
        // Звать `point(for:)` вне главного потока можно: Apple его
        // потокобезопасность не документирует, но MapKit сам зовёт
        // `draw(_:zoomScale:in:)` параллельно на нескольких фоновых потоках, и
        // любая реализация внутри зовёт `point(for:)` — по использованию это
        // контракт. А вызов ДО первой отрисовки держится тем, что система
        // координат рендерера выводится из `boundingMapRect` оверлея и
        // зафиксирована с `super.init`. Сломанный трансформ не молчал бы:
        // `MapRenderCostTests.testVeilTilesWithNoRoadsAreFarCheaperThanTilesWithThem`
        // сравнивает тайл над сетью с тайлом в 900 км от неё.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.index.prepare(
                source: { veil.layer.polylines(for: $0) },
                transform: { self.point(for: $0) }
            )
            // Один раз на жизнь рендерера: тайлы, нарисованные заливкой,
            // обязаны получить свои коридоры. По ходу поездки так звать
            // нельзя — прорезь перерисовывает КОРОБКУ (`FogRevealAnimation`).
            DispatchQueue.main.async { self.setNeedsDisplay() }
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

    /// Сколько ступеней пера класть на коридор.
    ///
    /// Четырнадцать нужны широкому коридору на улице: на альфе 1.0 терраса
    /// видна там, где на полупрозрачной вуали её съедала сама прозрачность. На
    /// среднем и дальнем уровне коридор — вена шириной в двенадцать экранных
    /// точек, и разницы между четырьмя ступенями и восемью на ней не видит
    /// никто, а платятся они полной пропускной способностью памяти на КАЖДОМ
    /// тайле — в тот самый момент, когда после зума наружу их разом просят
    /// десяток (спайк 15 сен).
    static func passes(forScreenWidth width: CGFloat, lod: RevealedLayer.LOD) -> Int {
        guard lod == .fine else { return 4 }
        return width > wideCorridorPoints ? 14 : 8
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
    /// `haze: false` — только рампа, без пятен: так рисуется тайл, пока индекс
    /// путей ещё собирается (дешевле некуда, и цвет тот же).
    static func depth(
        for mapRect: MKMapRect, lod: RevealedLayer.LOD, haze: Bool = true
    ) -> FogVeilPainter.Depth {
        let wave = mapRect.height * 6
        guard wave > 0 else { return .flat }
        func shade(_ y: Double) -> CGFloat {
            CGFloat(0.5 + 0.5 * sin(2 * Double.pi * y / wave))
        }
        return FogVeilPainter.Depth(
            top: shade(mapRect.minY),
            bottom: shade(mapRect.maxY),
            haze: haze ? FogVeilPainter.Haze(world: mapRect, cell: hazeCell(for: lod)) : nil
        )
    }

    /// Шаг сеялки дымки — фиксированная доля МИРА, по одной на уровень детали.
    ///
    /// Три значения, а не одно: сетка в 39 км, взятая на всех зумах, на улице
    /// накрыла бы весь экран одним пятном, а сетка в 5 км на стране дала бы
    /// тысячу пятен на тайл. Каждое из трёх примерно с тайл СВОЕГО уровня,
    /// поэтому на экране всегда полтора десятка пятен — и при этом узор
    /// прибит к миру: панорама его не двигает, а перерисовка не мигает.
    static func hazeCell(for lod: RevealedLayer.LOD) -> Double {
        switch lod {
        case .fine: return MKMapSize.world.width / 8_192   // ≈ 4.9 км
        case .mid:  return MKMapSize.world.width / 1_024   // ≈ 39 км
        case .far:  return MKMapSize.world.width / 128     // ≈ 313 км
        }
    }

    // MARK: Отрисовка

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let tile = rect(for: mapRect)
        let level = Self.lod(for: zoomScale)
        // Метров на точку карты зависит от широты, поэтому берётся у ЭТОГО
        // тайла, а не у середины сети: иначе коридор в Мурманске нарисован по
        // мерке Сочи.
        let metre = MKMapPointsPerMeterAtLatitude(
            MKMapPoint(x: mapRect.midX, y: mapRect.midY).coordinate.latitude)

        // Индекс ещё собирается — рисуем сплошную заливку. Ждать его здесь
        // нельзя: это поток отрисовки MapKit, и ожидание встало бы полосой
        // недогруженных тайлов на всём экране. Прорезь у машины при этом
        // рисуется всё равно: она не про сеть, а про «я здесь».
        guard let chunks = index.ready(for: level) else {
            FogVeilPainter.paint(
                context: context, paths: [], corridorWidth: 0, passes: 0,
                tileRect: tile, depth: Self.depth(for: mapRect, lod: level, haze: false),
                reveal: reveal(in: mapRect, zoomScale: zoomScale, metre: metre)
            )
            return
        }
        let width = Self.corridorWidth(zoomScale: zoomScale, metre: metre)

        // Запрос расширяется на половину штриха: бакет, чья линия лежит за
        // краем тайла, всё равно рисует в него — на дальнем зуме коридор шире
        // километра.
        let reach = Double(width) / 2 + 1
        let query = mapRect.insetBy(dx: -reach, dy: -reach)
        let paths = chunks.visiblePaths(in: query, zoomScale: zoomScale)

        FogVeilPainter.paint(
            context: context,
            paths: paths,
            corridorWidth: width,
            passes: Self.passes(forScreenWidth: width * zoomScale, lod: level),
            tileRect: tile,
            depth: Self.depth(for: mapRect, lod: level),
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
