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
/// 1. **Вуаль лежит НИЖЕ пинов и выше карты Apple** (`attach(inside:seat:)`).
///    Мест два, и выбирает их карта: «Атлас» садится ПОД контейнером
///    аннотаций (выше оверлеев — свои он с карты снимает), экран поездки и
///    экран записи — ПОД контейнером оверлеев (иначе вуаль спрятала бы под
///    собой саму линию поездки). Логотип Apple и «Legal» выше любого из двух
///    по построению: они сабвью САМОГО `MKMapView`, а вуаль живёт внутри
///    `_MKMapContentView`.
/// 2. **Наклон запрещён** (`isPitchEnabled = false`): перспективу аффинной
///    матрицей не выразить. Сторож — `VeilFrame.residual`. Поворот, наоборот,
///    выражается точно — им и живёт режим «по курсу» на записи.
/// 3. **За краем растра — ровный туман** (`letterbox`), маскированный
///    четырёхугольником растра, а не подложка ПОД растром: подложка светилась
///    бы сквозь прожжённые коридоры, и дыр не было бы видно вовсе.
/// 4. **Прорезь у машины на живой записи — маска, а не растр**
///    (`setLiveReveal`): она растёт шестьдесят раз в секунду, и перерисовка
///    под неё остановила бы карту.
final class FogVeilView: UIView {

    // MARK: Настройки

    /// Во сколько раз растр шире видимой области. За его краем показывается
    /// ровный туман, поэтому запас — это не «чтобы не было дыр», а «сколько
    /// щипка переживём без ровного края».
    static let defaultMargin: Double = 1.5
    /// Запас «Атласа». Два, а не полтора, и это ответ на «по краям видны
    /// подгружаемые квадратики» (владелец, устройство, 16 сен).
    ///
    /// Растр 1.5× переживает щипок ровно до полутора экранов; дальше край
    /// растра выезжает на экран, за ним начинается ровный туман — и там, где
    /// туман ровный, коридоров нет вовсе, то есть граница читается прямым
    /// швом по картинке. Два оставляет вдвое больше площади и переносит эту
    /// границу за пределы экрана на всём обычном щипке. Цена — память:
    /// 440×956 pt видимого при 2.0 и `renderScale` 1.5 это ≈ 16 МБ на растр
    /// (против 9 МБ при 1.5×), и растров живёт не больше двух.
    static let atlasMargin: Double = 2.0
    /// Запас для карты, которую можно ПОВЕРНУТЬ (экран записи в режиме «по
    /// курсу», полноэкранная карта поездки под двумя пальцами).
    ///
    /// Дело не в дырах: растр привязывается к `visibleMapRect`, а тот у
    /// повёрнутой карты — уже осевая коробка повёрнутого экрана, поэтому
    /// повёрнутый растр накрывает экран при любом запасе ≥ 1, а дополнение до
    /// экрана считает четырёхугольник (`letterboxPath`), которому поворот
    /// безразличен. Дело в ЦЕНЕ: коробка меняет форму вместе с курсом — на 45°
    /// она шире по каждой стороне в 1.41 раза, — и от запаса 1.5 остаётся
    /// шесть процентов, то есть полный кадр тумана на каждое движение пальцем.
    /// 2.2 ≈ 1.5 × 1.41 оставляет те же полтора, на которых стоит расписание
    /// перерисовки. Держит `testRotatingMarginKeepsItsSlackThroughAQuarterTurn`.
    static let rotatingMargin: Double = 2.2
    /// Запас ЭТОЙ вуали. Свойство, а не константа: три карты живут по разным
    /// правилам, а вуаль у них одна.
    let margin: Double
    /// Пикселей на точку экрана. Полтора, а не три: у тумана нет ни одной
    /// резкой границы, кроме перьевого края коридора, а память и время
    /// отрисовки растут квадратом.
    static let renderScale: CGFloat = 1.5
    /// Потолок растра в пикселях — страховка на больших экранах.
    static let maxPixels: Int = 6_000_000
    /// На сколько полос режется растр НА МЕДЛЕННОМ устройстве и только в
    /// покое. Три: полоса довозится отдельно и ложится на экран сразу, поэтому
    /// туман дорезается тремя короткими шагами вместо одного длинного.
    ///
    /// Полосы — лекарство от ДОЛГОГО кадра, а не правило. Пока кадр дешевле
    /// `bandThreshold`, они только вредят: три картинки приезжают в разные
    /// кадры, и на большом зуме это и есть те самые «подгружаемые квадратики»,
    /// которые владелец увидел по краям. Поэтому по умолчанию растр ОДИН, а
    /// три полосы включаются, только если замер первого полного кадра на ЭТОМ
    /// устройстве вышел дороже порога.
    static let bands = 3
    /// Дороже этого — режем на полосы. 120 мс: при `throttle` 0.2 с кадр,
    /// перевалив за половину окна расписания, начинает обгонять сам себя, и
    /// лучше показать треть картинки вовремя, чем всю с опозданием.
    static let bandThreshold: TimeInterval = 0.12
    /// Кроссфейд полосы при подмене растра — ТОЛЬКО в покое.
    ///
    /// Во время жеста подмена мгновенная: кроссфейд на движущейся карте — это
    /// полторы десятых секунды, в которые на экране лежат ДВА растра разного
    /// масштаба сразу, то есть «пьяная» анимация зума, о которой и написал
    /// владелец.
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
        /// Играла ли хоть одна полоса кроссфейд: по нему решается, ждать ли
        /// его конца, прежде чем снять прежний растр.
        var faded = false
        /// Где растр лежит НА ЭКРАНЕ прямо сейчас — четыре его угла по часовой
        /// стрелке. Считается той же матрицей, что и привязка слоя, поэтому
        /// верен и при повороте карты; пустой, пока привязки не было.
        var quad: [CGPoint] = []

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

    /// Ровный туман вокруг растра. Лежит НИЖЕ растров и маскируется их
    /// ЧЕТЫРЁХУГОЛЬНИКОМ на экране — не осевой коробкой: у повёрнутой карты
    /// коробка больше самого растра, и ровный туман залез бы под него, то есть
    /// подсветил бы изнутри каждый прожжённый коридор.
    private let letterbox = CALayer()
    private let letterboxMask = CAShapeLayer()
    /// Прорезь у машины на живой записи. Маска на СВОЁМ слое: она обязана
    /// резать и растр, и ровный туман вокруг него.
    private let revealMask = VeilRevealMask()
    private var liveReveal: (coordinate: CLLocationCoordinate2D, progress: Double, metres: Double)?
    /// Самое большее два: тот, что на экране, и тот, что въезжает поверх него.
    private var rasters: [Raster] = []

    private var index = MapPathIndex()
    private var indexReady = false
    private var revealed = RevealedLayer.empty
    private var visitedRegions: Set<String> = []
    /// Круги нерешённых загадок, уже переведённые в точки карты. Гравируются
    /// В РАСТР (`FogVeilPainter.engrave`), а не рисуются слоем аннотации:
    /// слой живёт в точках ЭКРАНА и во время щипка не пересчитывался — круг
    /// рос и сжимался относительно карты под ним.
    private var hints: [FogVeilPainter.EngravedHint] = []
    /// Чем узнаётся уже установленный слой: полилинии пересоздаются только
    /// вместе с ним.
    private var layerSignature: [ObjectIdentifier] = []
    private var hasLayer = false
    private var selectedPoints: [MKMapPoint] = []

    private var gate = VeilRenderGate()
    private var rendering = false
    private weak var map: MKMapView?

    private var displayLink: CADisplayLink?
    private var linkStopAt: Date = .distantPast

    /// Дерево карты, в которое вуаль встроена, и контейнер, под которым она
    /// сидит, — по ним проверяется, что она всё ещё на месте.
    private weak var attachedRoot: UIView?
    private weak var seatContainer: UIView?
    private var seat: Seat = .belowAnnotations
    /// Пересадка идёт прямо сейчас — см. `verifySeating`.
    private var reseating = false
    /// Вуаль потеряла своё место и вернуться не смогла: зовущий обязан
    /// вернуть на карту `FogVeilOverlay`.
    var onLostFromHierarchy: (() -> Void)?

    /// Поколение отрисовки: заказ, который успели обогнать, свою картинку не
    /// показывает и на фоне не досчитывается.
    private let genLock = NSLock()
    private var liveGeneration = 0
    private var generation = 0
    private let queue = DispatchQueue(label: "com.onezee.TripTrack.fogveil", qos: .userInitiated)

    /// Сколько раз гейт ПРОПУСТИЛ заказ растра. Им проверяется главное
    /// обещание прорези: она растёт, ничего не заказывая.
    var renderOrders: Int { gate.renders }
    /// Сколько раз слой ВООБЩЕ доходил до вуали. Читает тест «карта записи не
    /// дёргает `setLayer` шестьдесят раз в секунду»: сама вуаль на том же слое
    /// выходит рано, но подпись считает ДО выхода, и цена этого видна только
    /// счётом.
    private(set) var layerHandoffs = 0

    // MARK: Жизнь

    /// Рисует ли эта вуаль границы регионов и стран. Правда только у
    /// «Атласа»: на карте поездки и на записи они шум.
    let showsRegions: Bool

    init(margin: Double = FogVeilView.defaultMargin, showsRegions: Bool = false) {
        self.margin = margin
        self.showsRegions = showsRegions
        super.init(frame: .zero)
        // Хит-тест обязан проходить насквозь: под вуалью лежит сама карта, и
        // тап по дороге, пину и кластеру должен доходить до неё.
        isUserInteractionEnabled = false
        // Своего фона у вью нет нарочно: залитый цветом фон светился бы сквозь
        // прожжённые коридоры. Непрозрачность держат `letterbox` и растр,
        // которые вместе накрывают экран целиком.
        backgroundColor = .clear
        layer.masksToBounds = true
        letterbox.backgroundColor = FogVeilPainter.veilColorBottom.cgColor
        letterbox.actions = ["position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]
        letterboxMask.fillRule = .evenOdd
        letterboxMask.fillColor = UIColor.white.cgColor
        letterboxMask.actions = [
            "path": NSNull(), "position": NSNull(), "bounds": NSNull(),
        ]
        letterbox.mask = letterboxMask
        layer.addSublayer(letterbox)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    // MARK: Данные

    /// Открытый мир. Индекс путей собирается ОДИН раз и вне главного потока —
    /// по той же причине, что у `FogVeilRenderer`.
    func setLayer(_ incoming: RevealedLayer) {
        layerHandoffs += 1
        // Тот же слой — тот же индекс. `screenVeilTookOver` зовёт это на
        // КАЖДОМ появлении «Атласа», а сборка индекса стоит 10–13 мс на
        // главном потоке ожидания и вспышку «всё закрыто» на экране: до
        // готовности тайл рисуется заливкой без коридоров.
        let signature = incoming.polylines(for: .fine).map(ObjectIdentifier.init)
        if hasLayer, signature == layerSignature { return }
        hasLayer = true
        layerSignature = signature
        revealed = incoming
        // Посещённые — прямо из слоя: он и есть то, что передаёт вью-модель,
        // а второй источник этого списка однажды разошёлся бы с первым.
        visitedRegions = Set(incoming.regionKm.filter { $0.value > 0 }.map(\.key))
        indexReady = false
        gate.invalidate()
        // Свой индекс на каждый слой: `prepare` складывает наборы, а не
        // заменяет их, и переиспользованный индекс отдал бы старую сеть.
        let fresh = MapPathIndex()
        index = fresh
        queue.async { [weak self] in
            // Облака — синхронно и здесь же: очередь фоновая, а собранные
            // после первого растра они стоили бы второго полного кадра.
            CloudTexture.shared.prepare()
            if self?.showsRegions == true { RegionPathIndex.shared.prepareIfNeeded() }
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

    /// Круги подсказок — в метрах на земле, переводятся в точки карты один раз
    /// здесь, а не на каждый растр.
    ///
    /// Радиус считается по широте ЦЕНТРА круга: в Меркаторе точка карты — это
    /// разное число метров на разной широте, и круг, посчитанный по широте
    /// растра, на юге страны разошёлся бы с кругом на севере.
    func setHints(_ incoming: [RiddleHint]) {
        let converted = incoming.map { hint -> FogVeilPainter.EngravedHint in
            let metre = MKMapPointsPerMeterAtLatitude(hint.centre.latitude)
            let centre = MKMapPoint(hint.centre)
            return FogVeilPainter.EngravedHint(
                centre: CGPoint(x: centre.x, y: centre.y),
                radius: CGFloat(hint.radiusMetres * metre))
        }
        guard converted != hints else { return }
        hints = converted
        invalidate()
    }

    /// Сколько кругов подсказок гравируется — для теста.
    var engravedHintCount: Int { hints.count }

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

    // MARK: Прорезь у машины на живой записи

    /// Где и насколько раскрыт туман вокруг машины прямо сейчас.
    ///
    /// Растра это НЕ КАСАЕТСЯ. Прорезь растёт шестьдесят раз в секунду
    /// (`FogRevealAnimation`, 0.7 с), и заказать под неё перерисовку значило бы
    /// шестьдесят полных кадров в секунду по сорок миллисекунд каждый — то
    /// есть запись, у которой карта стоит. Поэтому дыра живёт маской на слое
    /// вуали: она режет и растр, и ровный туман за его краем, а трогает при
    /// этом четыре `frame` и один градиент.
    ///
    /// После финиша коридор по-настоящему прожигает уже слой открытого
    /// (`RevealedLayerStore`), новый растр приходит с ним, и маска снимается
    /// тем же `nil`, которым её завёл `MapViewModel.rebuildFog`.
    func setLiveReveal(coordinate: CLLocationCoordinate2D?, progress: Double) {
        setReveal(coordinate: coordinate, progress: progress,
                  metres: FogVeilRenderer.revealMetres)
    }

    /// Та же прорезь с другим радиусом — «печать проступает» на «Атласе»
    /// (`SealRevealAnimation`, 120 м за 0.6 с).
    ///
    /// Радиус параметром, а не константой внутри: у машины на записи он свой
    /// (150 м, `FogVeilRenderer.revealMetres`), и сведённые в одно число они
    /// разъехались бы при первой правке любого из двух. Маска при этом ОДНА —
    /// двух прорезей одновременно не бывает: запись и Атлас это разные экраны.
    func setReveal(
        coordinate: CLLocationCoordinate2D?,
        progress: Double,
        metres: Double = FogVeilRenderer.revealMetres
    ) {
        guard let coordinate, progress > 0 else {
            guard liveReveal != nil else { return }
            liveReveal = nil
            layer.mask = nil
            return
        }
        liveReveal = (coordinate, progress, metres)
        if layer.mask !== revealMask.layer { layer.mask = revealMask.layer }
        guard let map else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        positionLiveReveal(map: map)
        CATransaction.commit()
    }

    /// Стоит ли сейчас прорезь — для теста.
    var hasLiveReveal: Bool { liveReveal != nil }

    /// Отдали ли вуали слой открытого мира — для теста: им проверяется, что
    /// временной срез поездки доезжает до вуали, а не до снятого оверлея.
    var hasInstalledLayer: Bool { hasLayer }

    /// Ставит маску на место. Зовётся из `sync`, то есть на каждом кадре
    /// движения карты: прорезь привязана к ЗЕМЛЕ, а не к экрану.
    private func positionLiveReveal(map: MKMapView) {
        guard let live = liveReveal else { return }
        let centre = map.convert(live.coordinate, toPointTo: self)
        let metresPerPoint = map.metersPerScreenPoint
        guard metresPerPoint > 0, metresPerPoint.isFinite else { return }
        let radius = CGFloat(live.metres * live.progress / metresPerPoint)
        revealMask.update(bounds: bounds, centre: centre, radius: max(radius, 1))
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

    /// Куда именно садится вуаль в дереве карты.
    ///
    /// Разница между двумя местами — это разница между «оверлеев подо мной нет»
    /// и «оверлеи рисуют поверх меня», и она не косметическая.
    enum Seat {
        /// ПОД контейнером аннотаций, то есть ВЫШЕ оверлеев. «Атлас»: жилка
        /// сети и выбранный маршрут уходят в растр, а оверлеи с карты
        /// снимаются — под вуалью их не осталось.
        case belowAnnotations
        /// Над картой Apple, но ПОД контейнером оверлеев. Экран поездки и экран
        /// записи рисуют маршрут `MKOverlayRenderer`-ом — отрезками по скорости,
        /// с обводкой, с гашением непройденного на реплее и со светящейся
        /// головой на записи. Увести это в растр значило бы перерисовывать
        /// восьмимегабайтную картинку на каждом кадре реплея; посадить вуаль
        /// выше — спрятать под ней саму поездку.
        case aboveBaseMap
    }

    /// Ищет контейнер аннотаций. Имя класса приватное, поэтому ищем по
    /// ПОДСТРОКЕ имени и честно отваливаемся, если не нашли: ни одного
    /// приватного метода здесь не зовётся, только `subviews` и имя класса.
    static func annotationContainer(in root: UIView) -> UIView? {
        if let exact = firstView(in: root, matching: "AnnotationContainer") { return exact }
        // Второй заход — любой контейнер со словом Annotation в имени: имена
        // приватные, и Apple вправе их переписать.
        return firstView(in: root, matching: "Annotation")
    }

    /// Обход ВШИРЬ, и это не вкус. В снятом дереве контейнер аннотаций —
    /// прямая сабвью `_MKMapContentView`, но её сосед слева, `MKBasicMapView`,
    /// при обходе в глубину разбирается ЦЕЛИКОМ раньше. Любой приватный класс
    /// внутри хостинга карты со словом `Annotation` в имени увёл бы вуаль под
    /// слой Metal — молча, с `attach == true` и снятыми оверлеями, то есть без
    /// тумана вовсе. Вширь побеждает самый мелкий по глубине, а он и есть
    /// нужный.
    private static func firstView(in root: UIView, matching needle: String) -> UIView? {
        var queue = root.subviews
        var head = 0
        while head < queue.count {
            let view = queue[head]
            head += 1
            if NSStringFromClass(type(of: view)).contains(needle) { return view }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    /// Контейнер оверлеев — точнее, тот прямой сосед контейнера аннотаций, в
    /// котором `MKOverlayRenderer` рисует. В снятом дереве это
    /// `MKScrollContainerView` с `MKOverlayContainerView` внутри; ищем по обоим
    /// именам и берём САМОГО РАННЕГО по порядку сабвью — если контейнеров на
    /// уровень оверлеев окажется два, вуаль обязана лечь под нижний.
    static func overlayContainer(among siblings: [UIView]) -> UIView? {
        siblings.first { view in
            let name = NSStringFromClass(type(of: view))
            if name.contains("ScrollContainer") || name.contains("OverlayContainer") { return true }
            return firstView(in: view, matching: "OverlayContainer") != nil
        }
    }

    /// Ставит вуаль на своё место. `false` — иерархия незнакомая, зовущий
    /// обязан остаться на плиточном рендерере.
    ///
    /// Промах на `.aboveBaseMap` — это именно откат, а не «сядем куда
    /// придётся»: вуаль, севшая выше оверлеев, спрятала бы под собой линию
    /// поездки, а туман нарисовала бы точно так же, и заметить подмену было бы
    /// нечем.
    @discardableResult
    func attach(inside root: UIView, map: MKMapView? = nil, seat: Seat = .belowAnnotations) -> Bool {
        self.map = map ?? (root as? MKMapView)
        attachedRoot = root
        self.seat = seat
        guard let annotations = Self.annotationContainer(in: root),
              let parent = annotations.superview else {
            seatContainer = nil
            logFallback("контейнер аннотаций не найден")
            return false
        }
        let container: UIView
        switch seat {
        case .belowAnnotations:
            container = annotations
        case .aboveBaseMap:
            guard let overlays = Self.overlayContainer(among: parent.subviews) else {
                seatContainer = nil
                logFallback("контейнер оверлеев не найден")
                return false
            }
            container = overlays
        }
        frame = parent.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Место запоминается ДО вставки: `insertSubview` немедленно зовёт
        // `didMoveToWindow`, тот — `verifySeating`, а та по незаполненному
        // `seatContainer` решила бы, что сидим не там, и пересаживала бы себя
        // внутри собственной посадки.
        seatContainer = container
        parent.insertSubview(self, belowSubview: container)
        return true
    }

    /// Про откат рассказываем один раз за запуск — см. `loggedFallback`.
    private func logFallback(_ reason: String) {
        guard !Self.loggedFallback else { return }
        Self.loggedFallback = true
        Self.log.notice("экранная вуаль: \(reason, privacy: .public) — откат на FogVeilOverlay")
    }

    /// Сидит ли вуаль там, где её поставили: в том же родителе, что контейнер
    /// аннотаций, и НИЖЕ него.
    ///
    /// Проверяется каждый кадр движения, потому что цена ошибки несимметрична:
    /// плиточные оверлеи с карты уже сняты, и вуаль, вылетевшая из дерева
    /// (перестроение сабвью MapKit, восстановление после нехватки памяти,
    /// будущая iOS), оставит «Атлас» БЕЗ тумана вовсе — хуже, чем было до
    /// 0.7.0. Сама проверка — два `firstIndex` по пяти сабвью.
    func verifySeating() {
        guard let root = attachedRoot, !reseating else { return }
        if let parent = superview, let container = seatContainer,
           container.superview === parent,
           let mine = parent.subviews.firstIndex(of: self),
           let theirs = parent.subviews.firstIndex(of: container),
           mine < theirs { return }

        // Пересадка трогает дерево, а дерево зовёт `didMoveToWindow` — то есть
        // эту же проверку изнутри неё самой.
        reseating = true
        defer { reseating = false }
        removeFromSuperview()
        guard attach(inside: root, map: map, seat: seat) else {
            attachedRoot = nil
            Self.log.notice("экранная вуаль выпала из дерева карты — откат на FogVeilOverlay")
            onLostFromHierarchy?()
            return
        }
    }

    /// Экран ушёл — вуаль уходит с ним: восемь мегабайт растра и
    /// `CADisplayLink` не имеют права жить за кадром.
    func detach() {
        stopTracking()
        rendering = false
        dropRasters(keepingNewest: false)
        // Прорезь уходит вместе с растрами: вуаль, снятая и посаженная обратно
        // (уход и возврат экрана записи), иначе показала бы дыру в том месте
        // ЭКРАНА, где машина была до ухода, — до первого `sync`.
        setLiveReveal(coordinate: nil, progress: 0)
        map = nil
        // Корень забывается ПЕРЕД выходом из дерева: иначе ближайшая проверка
        // места вернула бы вуаль обратно на экран, с которого её только что
        // сняли.
        attachedRoot = nil
        seatContainer = nil
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
        verifySeating()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for raster in rasters { apply(frameOf: raster, map: map) }
        layoutLetterbox()
        positionLiveReveal(map: map)
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
        // Четыре угла ТОЙ ЖЕ матрицей: при повороте карты осевая коробка слоя
        // больше самого растра, и ровный туман, посчитанный по ней, залез бы
        // растру под низ.
        raster.quad = [
            veil.point(atX: 0, y: 0), veil.point(atX: 1, y: 0),
            veil.point(atX: 1, y: 1), veil.point(atX: 0, y: 1),
        ]

        // Невязки здесь больше нет НАРОЧНО: она стоила двух лишних `convert`
        // на каждый растр и на каждый кадр движения, а читателя у неё не было
        // ни одного. Правило «без наклона матрица точна» держат чистые
        // `VeilFrame.residual` в тестах — на настоящей проекции `MKMapView`
        // (`VeilSeatTests.testHeadingLeavesNoResidualWhilePitchDoes`).
    }

    /// Четырёхугольник, который НА САМОМ ДЕЛЕ непрозрачен прямо сейчас.
    ///
    /// Последний ПОЛНЫЙ растр, а не просто последний. Пустой растр, только что
    /// заказанный, накрывает экран по построению (запас ≥ 1.5×) — посчитать
    /// дополнение по нему значит объявить непрозрачным то, чего ещё нет, и
    /// кольцо вокруг старого растра станет прозрачным на все 20–120 мс
    /// отрисовки, а на ПЕРВОМ кадре «Атласа» прозрачным будет весь экран.
    /// Плиточные оверлеи к этому моменту уже сняты — там была бы голая карта
    /// Apple, то есть ровно то, ради чего вуаль и делалась.
    static func coveredQuad(rasters: [(quad: [CGPoint], isComplete: Bool)]) -> [CGPoint] {
        rasters.last(where: { $0.isComplete && $0.quad.count == 4 })?.quad ?? []
    }

    /// Где лежит ровный туман — весь экран МИНУС четырёхугольник растра.
    ///
    /// Путь с правилом «чётное-нечётное», а не четыре осевые полосы: полосами
    /// дополнение повёрнутого растра не выражается вовсе, а осевая коробка
    /// вместо самого растра либо оставила бы прозрачные углы (сырая карта
    /// Apple), либо подложила бы ровный туман ПОД коридоры — и те засветились
    /// бы изнутри вместо живой карты.
    ///
    /// Чистая функция: «ни одного прозрачного пикселя» и «ровный туман не лезет
    /// на растр» проверяются только счётом по точкам.
    static func letterboxPath(bounds full: CGRect, quad: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addRect(full)
        if quad.count == 4 {
            path.move(to: quad[0])
            for point in quad.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
        return path
    }

    #if DEBUG
    /// Насколько привязка растра отстала от карты — в точках экрана.
    ///
    /// Сравнивается ПОКАЗАННАЯ (`presentation()`) позиция слоя с той, которую
    /// матрица даёт для ТЕКУЩЕГО `visibleMapRect` на этом же кадре. Ноль —
    /// туман едет с картой пиксель в пиксель; больше нуля — коридор на кадр
    /// отстаёт от дороги под ним, и это видно глазами как «пьяная» анимация.
    ///
    /// Только в Debug и только для замера: в релизе у него нет читателя, а
    /// два лишних `convert` на кадр движения — цена, которую платить не за
    /// что.
    func syncLag(map: MKMapView) -> CGFloat? {
        guard let raster = rasters.last, raster.isComplete else { return nil }
        let r = raster.rect
        guard let frame = VeilFrame(
            p00: map.convert(MKMapPoint(x: r.minX, y: r.minY).coordinate, toPointTo: self),
            p10: map.convert(MKMapPoint(x: r.maxX, y: r.minY).coordinate, toPointTo: self),
            p01: map.convert(MKMapPoint(x: r.minX, y: r.maxY).coordinate, toPointTo: self),
            size: raster.sizePoints
        ) else { return nil }
        // `presentation()` в тестовом процессе без сцены пуст — тогда берём
        // модель слоя: вопрос «отстала ли привязка от камеры» она отвечает
        // так же, потому что действия слоя выключены и модель равна
        // показанному с точностью до кадра.
        let position = (raster.container.presentation() ?? raster.container).position
        let want = frame.centre
        return hypot(position.x - want.x, position.y - want.y)
    }
    #endif

    /// Что сейчас накрыто растром — для теста и для `layoutLetterbox`.
    var coveredQuadPoints: [CGPoint] {
        Self.coveredQuad(rasters: rasters.map { ($0.quad, $0.isComplete) })
    }

    private func layoutLetterbox() {
        letterbox.frame = bounds
        letterboxMask.frame = bounds
        letterboxMask.path = Self.letterboxPath(bounds: bounds, quad: coveredQuadPoints)
    }

    /// Вуаль вышла из окна — либо её сняли мы сами (`detach` уже забыл корень
    /// и сюда не дойдёт), либо MapKit пересобрал сабвью при НЕПОДВИЖНОЙ карте.
    /// Второй случай `sync` не ловит: `CADisplayLink` в покое погашен, а
    /// плиточные оверлеи уже сняты — экран остался бы без тумана до первого
    /// жеста.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        verifySeating()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        verifySeating()
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
                          settled: settled, margin: margin) else { return }
        render(map: map, gated: true, settled: settled)
    }

    /// На сколько полос резать ЭТОТ кадр.
    ///
    /// Во время жеста — всегда одна: гейт пускает сюда только исчерпание
    /// растра (видимое вылезло за край), и три картинки, приезжающие в разные
    /// кадры движущейся карты, читаются ровно как «подгружаемые квадратики».
    /// В покое — одна, пока замер первого полного кадра на этом устройстве
    /// уложился в `bandThreshold`.
    static func bandCount(settled: Bool, fullFrameCost: TimeInterval?) -> Int {
        guard settled else { return 1 }
        guard let cost = fullFrameCost, cost > bandThreshold else { return 1 }
        return bands
    }

    /// Сколько стоил полный кадр на этом устройстве. Меряется ОДИН раз — на
    /// первом же односполосном растре — и живёт до перезапуска: устройство
    /// между кадрами не меняется, а мерить каждый кадр значило бы менять
    /// расписание от того, был ли процессор занят чужой работой.
    private static let costLock = NSLock()
    private static var storedFullFrameCost: TimeInterval?
    static var fullFrameCost: TimeInterval? {
        costLock.lock(); defer { costLock.unlock() }
        return storedFullFrameCost
    }
    static func recordFullFrameCost(_ cost: TimeInterval) {
        costLock.lock()
        if storedFullFrameCost == nil { storedFullFrameCost = cost }
        costLock.unlock()
    }
    /// Только для теста: забыть замер устройства.
    static func forgetFullFrameCost() {
        costLock.lock(); storedFullFrameCost = nil; costLock.unlock()
    }

    private func render(map: MKMapView, gated: Bool = false, settled: Bool = true) {
        guard indexReady, bounds.width > 1, bounds.height > 1 else { return }
        if !gated {
            guard gate.allows(now: CACurrentMediaTime(),
                              needed: Self.renderRect(visible: map.visibleMapRect, margin: 1),
                              settled: true, margin: margin) else { return }
        }
        let visible = map.visibleMapRect
        let rect = Self.renderRect(visible: visible, margin: margin)
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
        let bands = FogVeilBitmap.bandRects(
            rect: rect, grid: grid,
            bands: Self.bandCount(settled: settled, fullFrameCost: Self.fullFrameCost))
        guard !bands.isEmpty else { return }
        // Кроссфейд — только в покое: на движущейся карте он держит на экране
        // ДВА растра разного масштаба сразу, и зум от этого «пьяный».
        let fades = settled

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
        let circles = hints
        let whole = bands.count == 1
        let wantsRegions: RegionPathIndex? = showsRegions ? .shared : nil
        let visited = visitedRegions

        for band in bands {
            if let ready = reusable?.band(for: band, scale: scale, sizePoints: sizePoints) {
                install(image: ready.image, band: band, drawn: ready.drawn,
                        token: token, faded: false)
                continue
            }
            queue.async { [weak self] in
                guard let self, self.isLive(token) else { return }
                let started = CACurrentMediaTime()
                let made = FogVeilBitmap.render(
                    whole: rect, band: band, sizePoints: sizePoints, scale: scale,
                    grid: grid, index: indexRef, selected: route, hints: circles,
                    regions: wantsRegions, visited: visited)
                // Меряем только ЦЕЛЫЙ кадр: по трети растра о цене полного
                // судить нельзя, а первый кадр вуали всегда целый.
                if whole { Self.recordFullFrameCost(CACurrentMediaTime() - started) }
                DispatchQueue.main.async {
                    guard let made else { self.finish(token: token) ; return }
                    self.install(image: made.image, band: band, drawn: made.drawnRect,
                                 token: token, faded: fades, bytes: made.bytes)
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
            raster.faded = true
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
        // Последний кадр жеста мог заказать отрисовку длиннее хвоста
        // `CADisplayLink` — тогда чёткий кадр под новый масштаб не заказал бы
        // никто, и туман остался бы растянутым до следующего жеста. Один
        // повтор после окна расписания это закрывает; если растр уже свежий,
        // `maybeRender` выйдет на первой же проверке.
        DispatchQueue.main.asyncAfter(deadline: .now() + VeilRenderGate.throttle + 0.02) {
            [weak self] in
            guard let self, let map = self.map, self.displayLink == nil else { return }
            self.maybeRender(map: map, settled: true)
        }
        // Прежний растр держится ровно до конца кроссфейда — иначе под
        // полупрозрачной полосой на мгновение показалась бы карта Apple.
        guard rasters.count > 1 else { layoutLetterbox(); return }
        let stale = rasters.removeFirst()
        // Мгновенная подмена (жест) — прежний растр уходит сразу: держать его
        // лишние полторы десятых секунды значит держать на экране две
        // картинки разного масштаба.
        let faded = rasters.last?.faded == true
        guard faded else {
            stale.container.removeFromSuperlayer()
            layoutLetterbox()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.crossfade) { [weak self] in
            stale.container.removeFromSuperlayer()
            self?.layoutLetterbox()
        }
        layoutLetterbox()
    }

    /// Под давлением памяти отдаём всё, кроме того, что сейчас на экране:
    /// два растра по восемь мегабайт (на «Атласе» с запасом 2.0 — по
    /// шестнадцать) — это ровно та цена, которую здесь платят, и половину
    /// её можно вернуть системе немедленно.
    @objc private func handleMemoryWarning() {
        genLock.lock(); liveGeneration += 1; generation = liveGeneration; genLock.unlock()
        rendering = false
        dropRasters(keepingNewest: true)
        // Если отдать пришлось всё, экран остался ровной заливкой: сырой карты
        // на нём нет, но и открытых дорог тоже. Заказываем кадр сразу, а не
        // ждём, пока человек тронет карту.
        if rasters.isEmpty, let map { render(map: map) }
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
    ///
    /// Кругов подсказок здесь НЕТ по умолчанию, и это не забывчивость:
    /// постером делятся, а нарисовать подсказку значит выдать то, ради чего
    /// загадка и существует (`AtlasSharePoster` — «на постер попадает только
    /// найденное»).
    static func render(
        rect: MKMapRect, sizePoints: CGSize, scale: CGFloat,
        index: MapPathIndex, selected: [MKMapPoint],
        hints: [FogVeilPainter.EngravedHint] = [],
        regions: RegionPathIndex? = nil, visited: Set<String> = []
    ) -> Band? {
        render(whole: rect, band: rect, sizePoints: sizePoints, scale: scale,
               grid: grid(sizePoints: sizePoints), index: index, selected: selected,
               hints: hints, regions: regions, visited: visited)
    }

    /// Одна полоса растра. `whole` задаёт систему координат и сетку тайлов,
    /// `band` — то, что на самом деле рисуется.
    static func render(
        whole: MKMapRect, band: MKMapRect, sizePoints: CGSize, scale: CGFloat,
        grid: Grid, index: MapPathIndex, selected: [MKMapPoint],
        hints: [FogVeilPainter.EngravedHint] = [],
        regions: RegionPathIndex? = nil, visited: Set<String> = []
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
                    depth: FogVeilRenderer.depth(for: tile, lod: lod, haze: chunks != nil),
                    // Облака кладутся ПО СВОЕМУ ТАЙЛУ, ровно как у плиточного
                    // рендерера: узор привязан к миру, поэтому картинка от
                    // разбиения не зависит, а тесный клип тайла оказался
                    // ощутимо дешевле одного прохода на всю полосу (замер:
                    // полный кадр улицы 75 мс против 87, кадр вращаемой карты
                    // 151 против 179).
                    clouds: chunks == nil ? nil : FogVeilRenderer.clouds(
                        for: tile, rect: CGRect(x: tile.minX, y: tile.minY,
                                                width: tile.width, height: tile.height),
                        lod: lod)
                )
            }
        }
        let bandBox = CGRect(x: band.minX, y: band.minY,
                             width: band.width, height: band.height)
        let clouds = FogVeilRenderer.clouds(for: band, rect: bandBox, lod: lod)
        // Границы — ОДИН раз на полосу (не на тайл): контуры приходят целыми
        // и клипа по тайлу не терпят, а внутри открытого их всё равно
        // прожигает то же перо, что и туман.
        if let paths = regions?.paths(in: band, lod: lod, visited: visited) {
            FogVeilPainter.paintRegions(
                context: context,
                regions: FogVeilPainter.RegionPaint(paths: paths, zoomScale: zoomScale))
        }
        if layers == 1 {
            FogVeilPainter.punch(
                context: context, corridors: paths, corridorWidth: width, passes: passes,
                clouds: clouds)
            context.endTransparencyLayer()
        }

        // Круги подсказок — ПОСЛЕ коридоров и вне слоя прозрачности: они
        // рисуются нормальным режимом и стирать им нечего. Отбираются по
        // своей полосе: у подсказки радиус до тридцати километров, у полосы
        // на улице — двести метров.
        if !hints.isEmpty {
            let near = hints.filter { hint in
                let reach = Double(hint.radius)
                    + Double(FogVeilPainter.hintRimWidthPoints) / Double(zoomScale)
                return MKMapRect(x: Double(hint.centre.x) - reach,
                                 y: Double(hint.centre.y) - reach,
                                 width: reach * 2, height: reach * 2).intersects(band)
            }
            FogVeilPainter.engrave(context: context, hints: near, zoomScale: zoomScale)
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
