import UIKit
import MapKit
import os

/// Экранная вуаль: туман одним растром поверх карты, который во время жеста
/// НЕ перерисовывается, а едет за картой аффинным преобразованием.
///
/// Зачем она есть. `MKOverlayRenderer` рисует тайлы ПО ЗАПРОСУ и только для
/// текущего масштаба, поэтому у площади, приехавшей на экран после щипка,
/// нашей отрисовки не существует вовсе — и там видна живая карта Apple,
/// которую туман обязан прятать. До 15 сентября дыру закрывала штора
/// (`MapZoomCurtain`), то есть чёрный прямоугольник на время зума; владелец
/// отверг её на устройстве теми самыми словами, ради которых туман и делался:
/// «надо видеть, куда приближаюсь». У растра эта площадь есть — он просто
/// растягивается, как растягиваются собственные плитки Apple.
///
/// Три вещи, без которых приём не работает и которые поэтому записаны здесь:
///
/// 1. **Вуаль лежит ПОД контейнером аннотаций** (`attach(inside:)`), то есть
///    выше карты и выше оверлеев, но ниже пинов, подписей регионов и точки «я
///    здесь». Логотип Apple и «Legal» оказываются выше по построению: они
///    сабвью САМОГО `MKMapView`, а вуаль живёт внутри `_MKMapContentView`.
/// 2. **Наклон запрещён** (`isPitchEnabled = false`): перспективу аффинной
///    матрицей не выразить. Сторож — `VeilFrame.residual`.
/// 3. **За краем растра — ровный туман полосами** (`letterbox`), а не подложка
///    ПОД растром: подложка светилась бы сквозь прожжённые коридоры, и дыр не
///    было бы видно вовсе.
final class FogVeilView: UIView {

    // MARK: Настройки

    /// Во сколько раз растр шире видимой области. За его краем показывается
    /// ровный туман, поэтому запас — это не «чтобы не было дыр», а «сколько
    /// щипка переживём без ровного края».
    static let margin: Double = 1.5
    /// Пикселей на точку экрана. Полтора, а не три: у тумана нет ни одной
    /// резкой границы, кроме перьевого края коридора, а память и время
    /// отрисовки растут квадратом.
    static let renderScale: CGFloat = 1.5
    /// Потолок растра в пикселях — страховка на больших экранах.
    static let maxPixels: Int = 6_000_000
    /// На сколько полос режется растр. Три: полоса довозится отдельно и
    /// ложится на экран сразу, поэтому после жеста туман дорезается тремя
    /// короткими шагами вместо одного длинного.
    static let bands = 3
    /// Кроссфейд полосы при подмене растра.
    static let crossfade: TimeInterval = 0.15
    /// Сколько ещё тянуть привязку после того, как камера встала: MapKit
    /// доводит инерцию и сам, уже без колбэков о начале движения.
    static let trackingTail: TimeInterval = 0.4

    private static let log = Logger(subsystem: "com.onezee.TripTrack", category: "fogveil")
    /// Про откат рассказываем ОДИН раз за запуск: он случается на каждой
    /// попытке встроиться, а строк в журнале от этого больше не становится.
    private static var loggedFallback = false

    // MARK: Растр

    /// Один растр: мировой прямоугольник, его размер в точках и полосы,
    /// каждая своим слоем.
    private final class Raster {
        let rect: MKMapRect
        let sizePoints: CGSize
        let scale: CGFloat
        let container = CALayer()
        var bands: [(rect: MKMapRect, drawn: MKMapRect, image: CGImage)] = []
        var bytes = 0
        var expected: Int

        init(rect: MKMapRect, sizePoints: CGSize, scale: CGFloat, expected: Int) {
            self.rect = rect
            self.sizePoints = sizePoints
            self.scale = scale
            self.expected = expected
            container.actions = [
                "position": NSNull(), "bounds": NSNull(),
                "transform": NSNull(), "sublayers": NSNull(),
            ]
        }

        var isComplete: Bool { bands.count >= expected }

        /// Готовая полоса ровно на этот мировой прямоугольник и тот же
        /// масштаб — её можно взять, не рисуя.
        func band(
            for band: MKMapRect, scale other: CGFloat, sizePoints other2: CGSize
        ) -> (image: CGImage, drawn: MKMapRect)? {
            guard abs(scale - other) < 0.0001,
                  abs(sizePoints.width - other2.width) < 0.5,
                  abs(sizePoints.height - other2.height) < 0.5 else { return nil }
            guard let hit = bands.first(where: { FogVeilBitmap.sameRect($0.rect, band) })
            else { return nil }
            return (hit.image, hit.drawn)
        }
    }

    /// Ровный туман вокруг растра, четырьмя полосами. Лежит НИЖЕ растров.
    private let letterbox: [CALayer] = (0..<4).map { _ in CALayer() }
    /// Самое большее два: тот, что на экране, и тот, что въезжает поверх него.
    private var rasters: [Raster] = []

    private var index = MapPathIndex()
    private var indexReady = false
    private var revealed = RevealedLayer.empty
    private var selectedPoints: [MKMapPoint] = []

    private var gate = VeilRenderGate()
    private var rendering = false
    private weak var map: MKMapView?

    private var displayLink: CADisplayLink?
    private var linkStopAt: Date = .distantPast

    /// Поколение отрисовки: заказ, который успели обогнать, свою картинку не
    /// показывает и на фоне не досчитывается.
    private let genLock = NSLock()
    private var liveGeneration = 0
    private var generation = 0
    private let queue = DispatchQueue(label: "com.onezee.TripTrack.fogveil", qos: .userInitiated)

    /// Числа для теста и отладки.
    private(set) var renderCount = 0
    private(set) var lastDriftCentre: CGFloat = 0
    private(set) var lastDriftCorner: CGFloat = 0
    var rasterBytes: Int { rasters.reduce(0) { $0 + $1.bytes } }

    // MARK: Жизнь

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Хит-тест обязан проходить насквозь: под вуалью лежит сама карта, и
        // тап по дороге, пину и кластеру должен доходить до неё.
        isUserInteractionEnabled = false
        // Своего фона у вью нет нарочно: залитый цветом фон светился бы сквозь
        // прожжённые коридоры. Непрозрачность держат `letterbox` и растр,
        // которые вместе накрывают экран целиком.
        backgroundColor = .clear
        layer.masksToBounds = true
        for box in letterbox {
            box.backgroundColor = FogVeilPainter.veilColorBottom.cgColor
            box.actions = ["position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]
            layer.addSublayer(box)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    // MARK: Данные

    /// Открытый мир. Индекс путей собирается ОДИН раз и вне главного потока —
    /// по той же причине, что у `FogVeilRenderer`.
    func setLayer(_ incoming: RevealedLayer) {
        revealed = incoming
        indexReady = false
        gate.invalidate()
        // Свой индекс на каждый слой: `prepare` складывает наборы, а не
        // заменяет их, и переиспользованный индекс отдал бы старую сеть.
        let fresh = MapPathIndex()
        index = fresh
        queue.async { [weak self] in
            fresh.prepare(
                // Тождественное преобразование: система координат растра — это
                // координаты `MKMapPoint`, ровно как у рендерера с мировым
                // `boundingMapRect`. Масштаб приезжает потом, через CTM.
                source: { incoming.polylines(for: $0) },
                transform: { CGPoint(x: $0.x, y: $0.y) }
            )
            DispatchQueue.main.async {
                guard let self, self.index === fresh else { return }
                self.indexReady = true
                if let map = self.map { self.render(map: map) }
            }
        }
    }

    /// Выбранная поездка рисуется В РАСТР: оверлеем она лежала бы под вуалью и
    /// исчезла бы совсем.
    func setSelectedRoute(_ line: MKPolyline?) {
        guard let line, line.pointCount > 1 else {
            guard !selectedPoints.isEmpty else { return }
            selectedPoints = []
            invalidate()
            return
        }
        let buffer = line.points()
        selectedPoints = (0..<line.pointCount).map { buffer[$0] }
        invalidate()
    }

    /// Всё, что лежит на экране, устарело: следующий заказ идёт без задержки.
    /// Зовётся на смену данных, на поворот устройства и на смену
    /// `additionalSafeAreaInsets` — там меняется не камера, а сам кадр.
    func invalidate() {
        gate.invalidate()
        guard let map else { return }
        render(map: map)
    }

    // MARK: Встраивание в иерархию MKMapView

    /// Ищет контейнер аннотаций. Имя класса приватное, поэтому ищем по
    /// ПОДСТРОКЕ имени и честно отваливаемся, если не нашли: ни одного
    /// приватного метода здесь не зовётся, только `subviews` и имя класса.
    static func annotationContainer(in root: UIView) -> UIView? {
        if let exact = firstView(in: root, matching: "AnnotationContainer") { return exact }
        // Второй заход — любой контейнер со словом Annotation в имени: имена
        // приватные, и Apple вправе их переписать.
        return firstView(in: root, matching: "Annotation")
    }

    private static func firstView(in root: UIView, matching needle: String) -> UIView? {
        for sub in root.subviews {
            if NSStringFromClass(type(of: sub)).contains(needle) { return sub }
            if let deeper = firstView(in: sub, matching: needle) { return deeper }
        }
        return nil
    }

    /// Ставит вуаль ПОД контейнер аннотаций. `false` — иерархия незнакомая,
    /// зовущий обязан остаться на плиточном рендерере.
    @discardableResult
    func attach(inside root: UIView, map: MKMapView? = nil) -> Bool {
        self.map = map ?? (root as? MKMapView)
        guard let container = Self.annotationContainer(in: root),
              let parent = container.superview else {
            if !Self.loggedFallback {
                Self.loggedFallback = true
                Self.log.notice(
                    "экранная вуаль: контейнер аннотаций не найден — откат на FogVeilOverlay")
            }
            return false
        }
        frame = parent.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        parent.insertSubview(self, belowSubview: container)
        return true
    }

    /// Экран ушёл — вуаль уходит с ним: восемь мегабайт растра и
    /// `CADisplayLink` не имеют права жить за кадром.
    func detach() {
        stopTracking()
        rendering = false
        dropRasters(keepingNewest: false)
        map = nil
        removeFromSuperview()
    }

    // MARK: Кадр за кадром

    func startTracking(tail: TimeInterval = trackingTail) {
        linkStopAt = Date().addingTimeInterval(tail)
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func extendTracking(tail: TimeInterval = trackingTail) {
        linkStopAt = Date().addingTimeInterval(tail)
    }

    func stopTracking() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        guard let map else { return stopTracking() }
        sync(map: map)
        let settling = Date() > linkStopAt
        if settling { stopTracking() }
        // Камера встала — здесь и только здесь заказывается ЧЁТКИЙ растр под
        // новый масштаб.
        maybeRender(map: map, settled: settling)
    }

    /// Привязка растров к карте. Три вызова `convert` дают аффинное
    /// преобразование ТОЧНО: без наклона проекция «мировые точки → экран» —
    /// это перенос, масштаб и поворот, и больше ничего.
    func sync(map: MKMapView) {
        guard !rasters.isEmpty else { layoutLetterbox(); return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for raster in rasters { apply(frameOf: raster, map: map) }
        layoutLetterbox()
        CATransaction.commit()
    }

    private func apply(frameOf raster: Raster, map: MKMapView) {
        let r = raster.rect
        let p00 = map.convert(MKMapPoint(x: r.minX, y: r.minY).coordinate, toPointTo: self)
        let p10 = map.convert(MKMapPoint(x: r.maxX, y: r.minY).coordinate, toPointTo: self)
        let p01 = map.convert(MKMapPoint(x: r.minX, y: r.maxY).coordinate, toPointTo: self)
        guard let veil = VeilFrame(p00: p00, p10: p10, p01: p01, size: raster.sizePoints)
        else { return }
        raster.container.bounds = CGRect(origin: .zero, size: raster.sizePoints)
        raster.container.position = veil.centre
        raster.container.setAffineTransform(veil.transform)

        // Невязка: четвёртый угол и центр считаем и матрицей, и картой. Если
        // карта наклонена, они разъедутся — и это единственный способ увидеть
        // уход коридора от дороги числом, а не «кажется, поехало».
        lastDriftCorner = veil.residual(
            measured: map.convert(MKMapPoint(x: r.maxX, y: r.maxY).coordinate, toPointTo: self),
            atX: 1, y: 1)
        lastDriftCentre = veil.residual(
            measured: map.convert(MKMapPoint(x: r.midX, y: r.midY).coordinate, toPointTo: self),
            atX: 0.5, y: 0.5)
    }

    /// Полосы ровного тумана — точное дополнение растра до экрана. Верно, пока
    /// карта не повёрнута (`isRotateEnabled = false` на «Атласе»), и это
    /// записанное ограничение, а не забытый случай.
    private func layoutLetterbox() {
        let full = bounds
        let f: CGRect = rasters.last.map { $0.container.frame } ?? .zero
        let rects = [
            CGRect(x: 0, y: 0, width: full.width, height: max(0, f.minY)),
            CGRect(x: 0, y: min(full.height, max(0, f.maxY)),
                   width: full.width, height: max(0, full.height - f.maxY)),
            CGRect(x: 0, y: max(0, f.minY), width: max(0, f.minX),
                   height: max(0, min(full.height, f.maxY) - max(0, f.minY))),
            CGRect(x: min(full.width, max(0, f.maxX)), y: max(0, f.minY),
                   width: max(0, full.width - f.maxX),
                   height: max(0, min(full.height, f.maxY) - max(0, f.minY))),
        ]
        for (box, rect) in zip(letterbox, rects) { box.frame = rect }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutLetterbox()
        if let map { maybeRender(map: map, settled: true) }
    }

    // MARK: Перерисовка

    /// Мировой прямоугольник растра — видимая область с запасом, обрезанная по
    /// миру. Чистая функция: её единственную имеет смысл проверять тестом.
    static func renderRect(visible: MKMapRect, margin: Double) -> MKMapRect {
        let dx = visible.width * (margin - 1) / 2
        let dy = visible.height * (margin - 1) / 2
        let grown = visible.insetBy(dx: -dx, dy: -dy)
        let world = MKMapRect.world
        let minX = max(world.minX, grown.minX), maxX = min(world.maxX, grown.maxX)
        let minY = max(world.minY, grown.minY), maxY = min(world.maxY, grown.maxY)
        guard maxX > minX, maxY > minY else { return visible }
        return MKMapRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func maybeRender(map: MKMapView, settled: Bool) {
        guard !rendering, indexReady else { return }
        let needed = Self.renderRect(visible: map.visibleMapRect, margin: 1)
        guard gate.allows(now: CACurrentMediaTime(), needed: needed,
                          settled: settled, margin: Self.margin) else { return }
        render(map: map, gated: true)
    }

    private func render(map: MKMapView, gated: Bool = false) {
        guard indexReady, bounds.width > 1, bounds.height > 1 else { return }
        if !gated {
            guard gate.allows(now: CACurrentMediaTime(),
                              needed: Self.renderRect(visible: map.visibleMapRect, margin: 1),
                              settled: true, margin: Self.margin) else { return }
        }
        let visible = map.visibleMapRect
        let rect = Self.renderRect(visible: visible, margin: Self.margin)
        // Масштаб берём у самой карты, а не из `bounds/visible`: так он верен
        // и при инсетах, и при любом положении листа.
        let a = map.convert(MKMapPoint(x: visible.minX, y: visible.midY).coordinate, toPointTo: self)
        let b = map.convert(MKMapPoint(x: visible.maxX, y: visible.midY).coordinate, toPointTo: self)
        let ppmp = hypot(b.x - a.x, b.y - a.y) / CGFloat(visible.width)
        guard ppmp.isFinite, ppmp > 0 else { return }

        var sizePoints = CGSize(width: max(1, CGFloat(rect.width) * ppmp),
                                height: max(1, CGFloat(rect.height) * ppmp))
        var scale = Self.renderScale
        let pixels = sizePoints.width * scale * sizePoints.height * scale
        if pixels > CGFloat(Self.maxPixels) {
            scale *= sqrt(CGFloat(Self.maxPixels) / pixels)
        }
        sizePoints = CGSize(width: sizePoints.width.rounded(), height: sizePoints.height.rounded())

        let grid = FogVeilBitmap.grid(sizePoints: sizePoints)
        let bands = FogVeilBitmap.bandRects(rect: rect, grid: grid, bands: Self.bands)
        guard !bands.isEmpty else { return }

        generation += 1
        let token = generation
        genLock.lock(); liveGeneration = token; genLock.unlock()
        rendering = true
        gate.raster = rect

        let incoming = Raster(rect: rect, sizePoints: sizePoints, scale: scale,
                              expected: bands.count)
        // Больше двух растров не живёт никогда: старый уходит сразу, не
        // дожидаясь кроссфейда, — восемь мегабайт на каждый.
        while rasters.count >= 2 { rasters.removeFirst().container.removeFromSuperlayer() }
        rasters.append(incoming)
        layer.addSublayer(incoming.container)
        if let map = self.map { apply(frameOf: incoming, map: map) }

        let reusable = rasters.count > 1 ? rasters[rasters.count - 2] : nil
        let route = selectedPoints
        let indexRef = index

        for band in bands {
            if let ready = reusable?.band(for: band, scale: scale, sizePoints: sizePoints) {
                install(image: ready.image, band: band, drawn: ready.drawn,
                        token: token, faded: false)
                continue
            }
            queue.async { [weak self] in
                guard let self, self.isLive(token) else { return }
                let made = FogVeilBitmap.render(
                    whole: rect, band: band, sizePoints: sizePoints, scale: scale,
                    grid: grid, index: indexRef, selected: route)
                DispatchQueue.main.async {
                    guard let made else { self.finish(token: token) ; return }
                    self.install(image: made.image, band: band, drawn: made.drawnRect,
                                 token: token, faded: true, bytes: made.bytes)
                }
            }
        }
    }

    private func isLive(_ token: Int) -> Bool {
        genLock.lock(); defer { genLock.unlock() }
        return liveGeneration == token
    }

    /// Готовая полоса ложится на экран СРАЗУ, а не ждёт остальных: под ней
    /// лежит прежний растр, поэтому дыр не появляется, а новая площадь
    /// довозится третями.
    private func install(
        image: CGImage, band: MKMapRect, drawn: MKMapRect,
        token: Int, faded: Bool, bytes: Int = 0
    ) {
        guard token == generation, let raster = rasters.last, raster.expected > 0 else { return }
        let ppmp = raster.sizePoints.width / CGFloat(raster.rect.width)
        let layerFrame = CGRect(
            x: CGFloat(drawn.minX - raster.rect.minX) * ppmp,
            y: CGFloat(drawn.minY - raster.rect.minY) * ppmp,
            width: CGFloat(drawn.width) * ppmp,
            height: CGFloat(drawn.height) * ppmp
        )
        let bandLayer = CALayer()
        bandLayer.actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull()]
        bandLayer.contentsScale = raster.scale
        bandLayer.magnificationFilter = .linear
        bandLayer.minificationFilter = .linear
        bandLayer.frame = layerFrame
        bandLayer.contents = image
        raster.container.addSublayer(bandLayer)
        raster.bands.append((band, drawn, image))
        raster.bytes += bytes

        if faded {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = Self.crossfade
            bandLayer.add(fade, forKey: "veilFade")
        }
        if raster.isComplete { finish(token: token) }
    }

    private func finish(token: Int) {
        guard token == generation else { return }
        rendering = false
        renderCount += 1
        // Прежний растр держится ровно до конца кроссфейда — иначе под
        // полупрозрачной полосой на мгновение показалась бы карта Apple.
        guard rasters.count > 1 else { layoutLetterbox(); return }
        let stale = rasters.removeFirst()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.crossfade) { [weak self] in
            stale.container.removeFromSuperlayer()
            self?.layoutLetterbox()
        }
        layoutLetterbox()
    }

    /// Под давлением памяти отдаём всё, кроме того, что сейчас на экране:
    /// два растра по восемь мегабайт — это ровно та цена, которую здесь
    /// платят, и половину её можно вернуть системе немедленно.
    @objc private func handleMemoryWarning() {
        genLock.lock(); liveGeneration += 1; generation = liveGeneration; genLock.unlock()
        rendering = false
        dropRasters(keepingNewest: true)
    }

    private func dropRasters(keepingNewest: Bool) {
        let keep = keepingNewest && rasters.last?.isComplete == true ? 1 : 0
        while rasters.count > keep {
            rasters.removeFirst().container.removeFromSuperlayer()
        }
        if keep == 0 { gate.invalidate() }
        layoutLetterbox()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        displayLink?.invalidate()
    }
}

// MARK: - Кисть в растр

/// Рисует туман в растр — полосами, а внутри полосы тайлами.
///
/// Тайлы нужны не ради скорости: от них зависит и рампа глубины, и сеялка
/// дымки (`FogVeilRenderer.depth`), — один кусок на весь экран дал бы другой
/// рисунок. А вот слой прозрачности открывается ОДИН на полосу, а не на тайл:
/// по замеру спайка (15 сен) цену полного кадра держит число тайлов, а не
/// число пикселей — 24 тайла дали 211 мс против 142 мс на 15 тайлах, потому
/// что каждый открывает свой буфер и кладёт до четырнадцати проходов пера.
enum FogVeilBitmap {
    struct Grid {
        let cols: Int
        let rows: Int
    }

    struct Band {
        /// Логический прямоугольник полосы — по нему полоса узнаётся при
        /// переиспользовании.
        let rect: MKMapRect
        /// Что на самом деле нарисовано: полоса плюс пиксель снизу. Соседние
        /// полосы — РАЗНЫЕ картинки, и на их общей границе при любом
        /// растяжении растра иначе остаётся волосяная щель в живую карту.
        let drawnRect: MKMapRect
        let image: CGImage
        let bytes: Int
        let tiles: Int
        /// Сколько раз открыт слой прозрачности. Считается там же, где
        /// зовётся `beginTransparencyLayer`, и ровно за этим: «один слой на
        /// растр» — обещание, которое иначе никто не проверит.
        let layers: Int
        let lod: RevealedLayer.LOD
    }

    /// Целевая сторона тайла в точках экрана.
    static let tilePoints: CGFloat = 256
    /// Потолок числа тайлов на растр.
    static let maxTiles = 128

    static func grid(sizePoints: CGSize) -> Grid {
        var cols = max(1, Int((sizePoints.width / tilePoints).rounded(.up)))
        var rows = max(1, Int((sizePoints.height / tilePoints).rounded(.up)))
        while cols * rows > maxTiles { cols = max(1, cols / 2); rows = max(1, rows / 2) }
        return Grid(cols: cols, rows: rows)
    }

    /// Полосы по вертикали — целым числом РЯДОВ тайлов.
    ///
    /// По рядам, а не по равным долям высоты: рампа глубины и сеялка дымки
    /// привязаны к границам тайлов, и полоса, разрезавшая тайл пополам,
    /// нарисовала бы его двумя разными градиентами — то есть шов.
    static func bandRects(rect: MKMapRect, grid: Grid, bands: Int) -> [MKMapRect] {
        guard rect.height > 0, grid.rows > 0, bands > 0 else { return [] }
        let count = min(bands, grid.rows)
        let tileH = rect.height / Double(grid.rows)
        var out: [MKMapRect] = []
        var first = 0
        for band in 0..<count {
            let last = grid.rows * (band + 1) / count
            guard last > first else { continue }
            out.append(MKMapRect(
                x: rect.minX, y: rect.minY + Double(first) * tileH,
                width: rect.width, height: Double(last - first) * tileH))
            first = last
        }
        return out
    }

    /// Совпадают ли мировые прямоугольники с точностью до ошибки округления —
    /// вопрос «можно ли взять готовую полосу, не рисуя её заново».
    static func sameRect(_ a: MKMapRect, _ b: MKMapRect) -> Bool {
        let tolerance = max(1e-6, a.width * 1e-9)
        return abs(a.minX - b.minX) < tolerance && abs(a.minY - b.minY) < tolerance
            && abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }

    /// Весь растр одной картинкой — постер, снапшот, тест стоимости.
    static func render(
        rect: MKMapRect, sizePoints: CGSize, scale: CGFloat,
        index: MapPathIndex, selected: [MKMapPoint]
    ) -> Band? {
        render(whole: rect, band: rect, sizePoints: sizePoints, scale: scale,
               grid: grid(sizePoints: sizePoints), index: index, selected: selected)
    }

    /// Одна полоса растра. `whole` задаёт систему координат и сетку тайлов,
    /// `band` — то, что на самом деле рисуется.
    static func render(
        whole: MKMapRect, band: MKMapRect, sizePoints: CGSize, scale: CGFloat,
        grid: Grid, index: MapPathIndex, selected: [MKMapPoint]
    ) -> Band? {
        guard whole.width > 0, whole.height > 0, band.width > 0, band.height > 0,
              sizePoints.width > 0, sizePoints.height > 0 else { return nil }
        let pixelsPerMapPoint = Double(sizePoints.width) * Double(scale) / whole.width
        // Пиксель припуска снизу: полосы — разные картинки, и без нахлёста их
        // общая граница светит живой картой Apple.
        let bleed = 1 / pixelsPerMapPoint
        let band = MKMapRect(x: band.minX, y: band.minY,
                             width: band.width, height: band.height + bleed)
        let px = max(1, Int((band.width * pixelsPerMapPoint).rounded()))
        let py = max(1, Int((band.height * pixelsPerMapPoint).rounded()))
        guard let context = CGContext(
            data: nil, width: px, height: py, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Система координат контекста = координаты `MKMapPoint`, y вниз.
        context.translateBy(x: 0, y: CGFloat(py))
        context.scaleBy(x: 1, y: -1)
        context.scaleBy(x: CGFloat(Double(px) / band.width), y: CGFloat(Double(py) / band.height))
        context.translateBy(x: CGFloat(-band.minX), y: CGFloat(-band.minY))

        let zoomScale = MKZoomScale(sizePoints.width / CGFloat(whole.width))
        let lod = FogVeilRenderer.lod(for: zoomScale)
        let chunks = index.ready(for: lod)

        // Ширина коридора — по широте СЕРЕДИНЫ полосы, а не каждого тайла.
        // Это и есть цена одного слоя на полосу: по всей её высоте метр на
        // точку карты считается одним числом. На кадре телефона полоса — это
        // треть экрана, и разница между её краями меньше промилле.
        let metre = MKMapPointsPerMeterAtLatitude(
            MKMapPoint(x: band.midX, y: band.midY).coordinate.latitude)
        let width = FogVeilRenderer.corridorWidth(zoomScale: zoomScale, metre: metre)
        let passes = FogVeilRenderer.passes(forScreenWidth: width * CGFloat(zoomScale), lod: lod)
        let reach = Double(width) / 2 + 1
        let paths = chunks?
            .visiblePaths(in: band.insetBy(dx: -reach, dy: -reach), zoomScale: zoomScale) ?? []

        let tileW = whole.width / Double(grid.cols)
        let tileH = whole.height / Double(grid.rows)
        var tiles = 0
        let layers = paths.isEmpty ? 0 : 1
        if layers == 1 { context.beginTransparencyLayer(auxiliaryInfo: nil) }
        for col in 0..<grid.cols {
            for row in 0..<grid.rows {
                let tile = MKMapRect(x: whole.minX + Double(col) * tileW,
                                     y: whole.minY + Double(row) * tileH,
                                     width: tileW, height: tileH)
                guard tile.intersects(band) else { continue }
                tiles += 1
                // Клип тайла сглаживается, и два соседа оставляют на общей
                // границе по половине пикселя — линию, сквозь которую видно
                // карту Apple. Полпикселя припуска в каждую сторону: сосед
                // накрывает шов своей же заливкой, а рампа глубины на этом
                // пикселе меняется меньше чем на уровень.
                let half = 0.5 / pixelsPerMapPoint
                FogVeilPainter.fillAndHaze(
                    context: context,
                    tile: CGRect(x: tile.minX - half, y: tile.minY - half,
                                 width: tile.width + half * 2, height: tile.height + half * 2),
                    depth: FogVeilRenderer.depth(for: tile, lod: lod, haze: chunks != nil)
                )
            }
        }
        if layers == 1 {
            FogVeilPainter.punch(context: context, corridors: paths,
                                 corridorWidth: width, passes: passes)
            context.endTransparencyLayer()
        }

        // Жилка сети — тем же индексом и теми же правилами, что у
        // `RouteVeinRenderer`: источник один, разъехаться им нельзя.
        if let chunks {
            drawVein(context: context, rect: band, chunks: chunks, zoomScale: zoomScale, lod: lod)
        }
        if selected.count > 1 {
            drawSelected(context: context, points: selected, zoomScale: zoomScale)
        }

        guard let image = context.makeImage() else { return nil }
        return Band(rect: MKMapRect(x: band.minX, y: band.minY,
                                   width: band.width, height: band.height - bleed),
                    drawnRect: band, image: image, bytes: context.bytesPerRow * py,
                    tiles: tiles, layers: layers, lod: lod)
    }

    private static func drawVein(
        context: CGContext, rect: MKMapRect, chunks: MapPathChunks,
        zoomScale: MKZoomScale, lod: RevealedLayer.LOD
    ) {
        let screenWidth = RouteVeinRenderer.width(for: lod)
        let widest = max(screenWidth, RouteVeinRenderer.halo(for: lod)?.width ?? 0)
            / CGFloat(zoomScale)
        let paths = chunks.visiblePaths(
            in: rect.insetBy(dx: -Double(widest) - 1, dy: -Double(widest) - 1),
            zoomScale: zoomScale)
        guard !paths.isEmpty else { return }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        if let halo = RouteVeinRenderer.halo(for: lod) {
            let metre = MKMapPointsPerMeterAtLatitude(
                MKMapPoint(x: rect.midX, y: rect.midY).coordinate.latitude)
            let ceiling = FogVeilRenderer.corridorWidth(zoomScale: zoomScale, metre: metre) * 1.2
            context.beginPath()
            paths.forEach(context.addPath)
            context.setLineWidth(min(halo.width / CGFloat(zoomScale), ceiling))
            context.setStrokeColor(
                RouteVeinRenderer.veinColor.withAlphaComponent(halo.alpha).cgColor)
            context.strokePath()
        }
        context.beginPath()
        paths.forEach(context.addPath)
        context.setLineWidth(screenWidth / CGFloat(zoomScale))
        context.setStrokeColor(RouteVeinRenderer.veinColor.withAlphaComponent(0.9).cgColor)
        context.strokePath()
    }

    private static func drawSelected(
        context: CGContext, points: [MKMapPoint], zoomScale: MKZoomScale
    ) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: points[0].x, y: points[0].y))
        for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.beginPath()
        context.addPath(path)
        context.setLineWidth((RouteVeinRenderer.selectedWidth + RouteVeinRenderer.casingExtra)
                             / CGFloat(zoomScale))
        context.setStrokeColor(RouteVeinRenderer.casingColor.cgColor)
        context.strokePath()
        context.beginPath()
        context.addPath(path)
        context.setLineWidth(RouteVeinRenderer.selectedWidth / CGFloat(zoomScale))
        context.setStrokeColor(RouteVeinRenderer.selectedColor.cgColor)
        context.strokePath()
    }
}
