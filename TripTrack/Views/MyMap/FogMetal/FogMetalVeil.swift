import MapKit
import MetalKit
import UIKit
import os

/// Метал-туман «Атласа».
///
/// Растровая вуаль (`FogVeilView`) рисует мглу раз в двести миллисекунд и
/// везёт готовую картинку за картой аффинным преобразованием слоя: на жесте
/// она мылится, после жеста видно «перезагрузку», а перья коридора ложатся
/// кольцами. Здесь весь туман собирается заново КАЖДЫЙ кадр, на GPU, из
/// отрезков открытого пути — поэтому ни растягивать, ни перезаказывать нечего.
///
/// Два прохода (`FogShaders.metal`): покрытие открытого в однобайтовую
/// текстуру со смешиванием `max` (стык отрезков не даёт ни бусины, ни кольца)
/// и композит ровной мглы поверх карты с премультиплицированной альфой.
///
/// Сам кадр кодирует `FogFrameEncoder` — тот же, которым рисует без экрана
/// `FogOffscreen`: картинка постера обязана совпасть с картинкой экрана, а
/// два кода, считающих одно и то же, однажды разойдутся молча.
///
/// Чего здесь нарочно НЕТ: облаков, рампы глубины, подписей регионов,
/// гравировки подсказок, выреза под атрибуцией и живой прорези у машины.
/// Картинка, которую эта вуаль показывает, — эталон 0.8.0 и менять её не
/// имеет права ни одна задача: числа перечислены в спеке
/// `docs/superpowers/specs/2026-09-22-080-fog-metal-design.md` §3.
@MainActor
final class FogMetalVeil: MTKView {
    private static let log = Logger(subsystem: "com.onezee.TripTrack", category: "fogmetal")

    /// Ширина пера — доля полуширины коридора. Та же мягкость, что у кисти
    /// растра, только считается на GPU в каждом кадре.
    ///
    /// `nonisolated`, потому что то же число спрашивает офскрин
    /// (`FogOffscreen.params`), а он рисует без экрана и без главного актёра.
    nonisolated static let featherRatio: Double = 0.4

    /// Сколько ещё тикаем после последнего движения карты.
    ///
    /// То же число и тот же смысл, что у растровой вуали
    /// (`FogVeilView.trackingTail`): палец отпущен, а карта ещё доезжает
    /// инерцией, и гасить `CADisplayLink` на каждой паузе между двумя
    /// уведомлениями значило бы заводить его заново по десять раз за жест.
    /// Своё число, а не чужое, нарочно: растровая вуаль эту карту однажды
    /// покинет, а хвост останется.
    nonisolated static let trackingTail: TimeInterval = 0.4

    private let queue: MTLCommandQueue
    /// Кодировщик кадра — ОДИН и тот же, что у офскрина: картинка экрана и
    /// картинка постера обязаны совпасть.
    private let encoder: FogFrameEncoder

    private var mesh = FogMesh.empty
    private var meshDirty = true
    /// Слой, который уже собран. `nil` — не собирали ни разу.
    private var installedSignature: [ObjectIdentifier]?
    /// Поколение сборки: слой, который успели обогнать, свои буферы не ставит.
    private var meshToken = 0

    private var coverage: MTLTexture?

    private weak var map: MKMapView?
    private var link: CADisplayLink?
    /// Когда `CADisplayLink` пора снять. Живёт вместе с ним и продлевается
    /// каждым движением карты.
    private var linkStopAt = Date.distantPast

    /// Кадр «вне камеры» уже заказан: тема или раскладка попросили
    /// перерисовку на СТОЯЩЕЙ карте. Пока камера не тронулась и данные те же,
    /// второй такой заказ нарисовал бы ровно ту же картинку, поэтому он
    /// молчит. Снимается всем, что меняет кадр само: движением
    /// (`startTracking`), разметкой, новым слоем и привязкой к карте.
    private var restFrameDrawn = false

    /// Палитра, с которой взялись рисовать последний кадр. Тема — то
    /// единственное, что зовёт `invalidate()`, и перещёлкнутая на СТОЯЩЕЙ
    /// карте дважды она обязана доехать оба раза: сравнение с этим числом и
    /// есть разница между «второй заказ той же картинки» и «второй сменой».
    private var drawnPaletteIsDark: Bool?

    /// Последний нарисованный кадр: прямоугольник карты и три его угла на
    /// экране. Совпало — GPU не трогаем вовсе, иначе на стоящей карте мы жгли
    /// бы батарею сто двадцать раз в секунду.
    private var lastRect: MKMapRect?
    private var lastCorners: [CGPoint] = []

    /// Сколько раз мы взялись рисовать кадр и сколько времени ушло на
    /// кодирование — для замера «сколько это стоит процессору».
    ///
    /// `frames` считается ПО ВЫЗОВУ `draw(_:)`, а не по доехавшему до экрана
    /// кадру: вид без окна `currentDrawable` не даёт вовсе, и счёт «только
    /// нарисованного» молчал бы в тестах, ради которых число и открыто
    /// наружу. Вопрос у него один — «тикаем мы в покое или нет».
    private(set) var frames = 0
    private(set) var encodeSeconds: Double = 0

    /// `nil` — на этом устройстве Metal недоступен или шейдеры не собрались:
    /// зовущий остаётся на растровой вуали, как до 0.8.0.
    ///
    /// Фабрикой, а не `init?()`: у `UIView` свой непроваливающийся `init()`,
    /// и переопределить его провальным Swift не даёт.
    static func make() -> FogMetalVeil? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let encoder = FogFrameEncoder(device: device) else { return nil }
        return FogMetalVeil(device: device, queue: queue, encoder: encoder)
    }

    private init(device: MTLDevice, queue: MTLCommandQueue, encoder: FogFrameEncoder) {
        self.queue = queue
        self.encoder = encoder
        super.init(frame: .zero, device: device)

        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        isOpaque = false
        layer.isOpaque = false
        backgroundColor = .clear
        framebufferOnly = true
        // Кадр заказываем сами, с `CADisplayLink`: рисовать по расписанию
        // MTKView значит рисовать и на стоящей карте.
        isPaused = true
        enableSetNeedsDisplay = false
        // Жесты обязаны доходить до карты под нами.
        isUserInteractionEnabled = false
    }

    required init(coder: NSCoder) { fatalError("init(coder:) не используется") }

    // MARK: Данные

    /// Открытый мир. Буферы собираются вне главного потока и подменяются
    /// целиком — дозаписи в живой буфер нет: кадр может идти прямо сейчас.
    func setLayer(_ revealed: RevealedLayer) {
        let signature = FogMesh.signature(of: revealed)
        guard signature != installedSignature, let device else { return }
        installedSignature = signature
        meshToken += 1
        let token = meshToken
        Task.detached(priority: .userInitiated) {
            let built = FogMesh.build(layer: revealed, device: device)
            await MainActor.run { [weak self] in
                guard let self, token == self.meshToken else { return }
                self.mesh = built
                self.meshDirty = true
                self.restFrameDrawn = false
                self.redrawIfNeeded()
            }
        }
    }

    // MARK: Жизнь

    /// Запоминает карту и рисует ОДИН кадр. `CADisplayLink` здесь не
    /// заводится: пока карта стоит, каждый его тик спрашивал бы у неё три
    /// `convert` и выбрасывал ответ — сто двадцать раз в секунду всё время,
    /// что открыт «Атлас». Тиками командует хост из делегата карты, теми же
    /// вызовами, что и растровой вуалью.
    func attach(map: MKMapView) {
        self.map = map
        meshDirty = true
        restFrameDrawn = false
        redrawIfNeeded()
    }

    func detach() {
        stopTracking()
        map = nil
        coverage = nil
    }

    // MARK: Жест

    /// Карта тронулась: заводим `CADisplayLink` и назначаем ему хвост. Второй
    /// вызов подряд хвост продлевает, а второй ссылки не заводит — ровно как
    /// у `FogVeilView`, откуда эта модель и взята.
    func startTracking(tail: TimeInterval = trackingTail) {
        linkStopAt = Date().addingTimeInterval(tail)
        // Кадр покоя больше ни про что: камера едет, и рисовать её будет сам
        // `CADisplayLink`.
        restFrameDrawn = false
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Камера встала: досматриваем хвост и гаснем сами, в `tick`.
    func extendTracking(tail: TimeInterval = trackingTail) {
        linkStopAt = Date().addingTimeInterval(tail)
    }

    func stopTracking() {
        link?.invalidate()
        link = nil
    }

    /// Идёт ли жест. `true` с `startTracking` и до тика, на котором вышел
    /// хвост, — именно до него, а не до самого дедлайна: снимает ссылку `tick`.
    var isTracking: Bool { link != nil }

    @objc private func tick() {
        guard map != nil else { return stopTracking() }
        redrawIfNeeded()
        if Date() > linkStopAt { stopTracking() }
    }

    /// Всё, что на экране, устарело не по камере: хост сменил тему. Рисуем
    /// один кадр сейчас.
    ///
    /// Ровно один: мгла собирается заново КАЖДЫЙ кадр, и второй зов подряд на
    /// той же камере, тех же данных и той же палитре дал бы ту же картинку.
    /// А сменившаяся палитра этот запрет снимает — иначе тема, перещёлкнутая
    /// туда и обратно на стоящей карте, застряла бы до первого движения
    /// пальца.
    func invalidate() {
        if drawnPaletteIsDark != FogVeilPainter.palette.isDark { restFrameDrawn = false }
        guard !restFrameDrawn else { return }
        restFrameDrawn = true
        meshDirty = true
        redrawIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        meshDirty = true
        restFrameDrawn = false
        redrawIfNeeded()
    }

    // MARK: Кадр

    /// Кадр рисуется только если камера сдвинулась или сменились данные.
    private func redrawIfNeeded() {
        guard let map, bounds.width > 1, bounds.height > 1 else { return }
        let rect = map.visibleMapRect
        let corners = Self.corners(of: rect, map: map, in: self)
        if !meshDirty, let last = lastRect, Self.sameRect(last, rect), corners == lastCorners {
            return
        }
        lastRect = rect
        lastCorners = corners
        meshDirty = false
        draw()
    }

    private static func sameRect(_ a: MKMapRect, _ b: MKMapRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5
            && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }

    /// Три угла прямоугольника карты на экране — левый верхний, правый верхний,
    /// левый нижний. Тот же приём, что у `VeilFrame`: без наклона проекция
    /// аффинна, и трёх точек ей хватает.
    private static func corners(of rect: MKMapRect, map: MKMapView, in space: UIView) -> [CGPoint] {
        [
            MKMapPoint(x: rect.minX, y: rect.minY),
            MKMapPoint(x: rect.maxX, y: rect.minY),
            MKMapPoint(x: rect.minX, y: rect.maxY),
        ].map { map.convert($0.coordinate, toPointTo: space) }
    }

    /// Кадр целиком. Считается он ЗДЕСЬ и до первой проверки: «взялись
    /// рисовать» и есть то, что меряет `frames`, — иначе вид без окна, где
    /// `currentDrawable` пуст, выглядел бы для тестов покоя вечно спящим.
    override func draw(_ rect: CGRect) {
        frames += 1
        drawnPaletteIsDark = FogVeilPainter.palette.isDark
        // Слоя ещё нет (вид только что встал в дерево) — кадр пропускаем, но
        // ПАМЯТЬ о нём стираем: иначе `redrawIfNeeded` посчитал бы кадр
        // нарисованным и молчал бы до первого движения камеры.
        guard let map, let device, let drawable = currentDrawable,
              let pass = currentRenderPassDescriptor,
              let buffer = queue.makeCommandBuffer() else { lastRect = nil; return }
        let started = CACurrentMediaTime()

        // Прямоугольник и углы берутся ТЕ ЖЕ, что посчитал `redrawIfNeeded`:
        // второй опрос карты дал бы другой кадр, и туман разъехался бы с ней
        // ровно на одно движение пальца.
        let visible = lastRect ?? map.visibleMapRect
        let corners = lastCorners.count == 3 ? lastCorners
            : Self.corners(of: visible, map: map, in: self)
        guard let frame = VeilFrame(p00: corners[0], p10: corners[1], p01: corners[2],
                                    size: CGSize(width: visible.width, height: visible.height))
        else { return }

        // Метры на экранную точку и полуширина ореола — те же функции, что у
        // растровой вуали: метал обязан показывать ТУ ЖЕ ширину открытого, а
        // не свою.
        let pointsPerMapPoint = Double(map.bounds.width) / visible.width
        let centreLat = MKMapPoint(x: visible.midX, y: visible.midY).coordinate.latitude
        let metresPerPoint = MKMetersPerMapPointAtLatitude(centreLat) / pointsPerMapPoint
        let halfWidth = FogVeilRenderer.haloHalfWidth(metresPerPoint: metresPerPoint) / metresPerPoint
        let params = FogFrameParams(
            frame: frame,
            visible: visible,
            viewportPoints: bounds.size,
            drawableSize: drawableSize,
            halfWidthPoints: halfWidth,
            featherPoints: halfWidth * Self.featherRatio,
            lod: FogVeilRenderer.lod(for: MKZoomScale(pointsPerMapPoint)),
            palette: FogVeilPainter.palette)

        // Текстура покрытия пережила прошлый кадр — её не стало только если
        // сменился размер или память отобрали. Не создалась вовсе — кадр
        // выходит пустым, но `present` всё равно нужен: иначе drawable
        // остался бы у нас на руках.
        if let coverage = coverageTexture(device: device) {
            encoder.encode(mesh: mesh, params: params, coverage: coverage,
                           target: pass, into: buffer)
        }

        buffer.present(drawable)
        buffer.commit()
        encodeSeconds += CACurrentMediaTime() - started
        // Цена кодирования на процессоре — то единственное число, ради
        // которого кадр и меряется. Раз в сто двадцать кадров, чтобы
        // сам замер не стоил дороже.
        if frames % 120 == 0 {
            let perFrame = String(format: "%.2f", encodeSeconds / Double(frames) * 1000)
            let line = "метал-туман: \(frames) кадров, кодирование \(perFrame) мс/кадр"
            Self.log.notice("\(line, privacy: .public)")
        }
    }

    private func coverageTexture(device: MTLDevice) -> MTLTexture? {
        let width = max(1, Int(drawableSize.width))
        let height = max(1, Int(drawableSize.height))
        if let texture = coverage, texture.width == width, texture.height == height {
            return texture
        }
        coverage = FogFrameEncoder.makeCoverageTexture(device: device, width: width, height: height)
        if coverage == nil { Self.log.notice("метал-туман: текстура покрытия не создалась") }
        return coverage
    }
}
