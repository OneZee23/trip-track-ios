import MapKit
import MetalKit
import UIKit
import os

/// Метал-туман: «Атлас», карта поездки и карта записи.
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
/// Чего здесь нарочно НЕТ: облаков, рампы глубины, подписей регионов и
/// гравировки подсказок. Картинка, которую эта вуаль показывает, — эталон
/// 0.8.0 и менять её не имеет права ни одна задача: числа перечислены в спеке
/// `docs/superpowers/specs/2026-09-22-080-fog-metal-design.md` §3.
///
/// Поверх эталона мгла знает ровно две вещи, и обе не про картинку тумана.
/// Окно под подписью Apple (`setAttributionCarve`) — про читаемость чужой
/// подписи под мглой, без него «Legal» на ночной мгле не виден. И прорезь у
/// машины на живой записи (`setLiveReveal`) — состояние одной секунды на
/// одном экране; у растровой вуали она маска на слое, потому что перерисовать
/// растр шестьдесят раз в секунду нельзя, а здесь кадр и так собирается
/// заново и дыра стоит двух чисел в буфере.
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

    /// В фоне ли приложение прямо сейчас — и, значит, запрещено ли трогать
    /// GPU (см. `draw(_:)`).
    ///
    /// Швом, а не прямым вызовом: подменить `UIApplication.applicationState`
    /// в тесте нечем, а правило слишком дорогое, чтобы остаться без сторожа —
    /// его нарушение это не мигнувший кадр, а убитый системой процесс.
    var isBackgrounded: @MainActor () -> Bool = {
        UIApplication.shared.applicationState == .background
    }

    private let queue: MTLCommandQueue
    /// Кодировщик кадра — ОДИН и тот же, что у офскрина: картинка экрана и
    /// картинка постера обязаны совпасть.
    private let encoder: FogFrameEncoder

    private var mesh = FogMesh.empty
    /// Кадр надо нарисовать, даже если камера та же: сменились данные,
    /// разметка, тема или прорезь у машины.
    ///
    /// Имя про КАДР, а не про буферы: сборку `FogMesh` этот флаг не заказывает
    /// никогда — её заказывает только новый слой. До перевода двух карт он
    /// звался `meshDirty`, и третьим его пользователем стала живая прорезь,
    /// которая к буферам не имеет отношения вовсе.
    private var frameDirty = true
    /// Слой, который уже собран. `nil` — не собирали ни разу. Открыто ради
    /// сторожа проводки: вопрос «дошёл ли до GPU срез ИМЕННО ЭТОЙ даты» иначе
    /// не задаётся ничем.
    private(set) var installedSignature: [ObjectIdentifier]?
    /// Сколько раз буферы открытого мира собирались заново.
    ///
    /// Читает это сторож живой прорези: она растёт шестьдесят раз в секунду, и
    /// пересборка буферов на каждый её кадр была бы записью, у которой карта
    /// стоит.
    private(set) var meshBuilds = 0
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

    /// Окно под подписью Apple. `nil` — выреза нет: либо тема светлая, либо
    /// атрибуции не нашлось. Ставит его ХОСТ, ровно там же, где отдаёт окно
    /// растровой вуали.
    private var carve: FogCarveWindow?
    /// Стиль «Клетки». Смена перерисовывает кадр даже на стоящей карте — на
    /// ней тика нет, и без этого зова стиль доехал бы только с первым
    /// движением пальца (та же причина, что у смены темы).
    private var usesCells = false
    /// Окно, с которым взялись рисовать последний кадр, — вторая половина
    /// ключа «кадр покоя уже нарисован». Окно ездит вместе с разметкой и
    /// высотой листа, и сдвинувшееся на СТОЯЩЕЙ карте оно обязано доехать до
    /// экрана само: ждать движения пальца значило бы держать подпись Apple
    /// под полной мглой ровно до него.
    private var drawnCarve: FogCarveWindow?
    /// Квантовал ли последний нарисованный кадр открытое клетками.
    ///
    /// Третий ключ латча «кадр покоя нарисован», наравне с палитрой и вырезом.
    /// Без него смена стиля на СТОЯЩЕЙ карте применялась наполовину: палитра
    /// доезжала (её ключ был), а клетки оставались прежними до первого
    /// движения пальцем — `invalidate()` выходил на `restFrameDrawn`.
    private var drawnUsesCells: Bool?

    /// Последний нарисованный кадр: прямоугольник карты и три его угла на
    /// экране. Совпало — GPU не трогаем вовсе, иначе на стоящей карте мы жгли
    /// бы батарею сто двадцать раз в секунду.
    private var lastRect: MKMapRect?
    private var lastCorners: [CGPoint] = []

    /// Сколько раз мы взялись рисовать кадр и сколько времени ушло на
    /// кодирование — для замера «сколько это стоит процессору».
    ///
    /// `frames` считается ПО ВЫЗОВУ `draw(_:)`, а не по доехавшему до экрана
    /// кадру: вид без окна drawable может и не выдать, и счёт «только
    /// нарисованного» молчал бы в тестах, ради которых число и открыто
    /// наружу. Вопрос у него один — «тикаем мы в покое или нет».
    ///
    /// Кадр, пропущенный фоном, сюда не попадает: за него мы не брались
    /// вовсе, и именно этим тест отличает «в фоне GPU не трогаем» от «в фоне
    /// рисуем, но в пустоту».
    private(set) var frames = 0
    private(set) var encodeSeconds: Double = 0

    /// `nil` — на этом устройстве Metal недоступен или шейдеры не собрались:
    /// зовущий остаётся на растровой вуали, как до 0.8.0.
    ///
    /// Фабрикой, а не `init?()`: у `UIView` свой непроваливающийся `init()`,
    /// и переопределить его провальным Swift не даёт.
    /// - Parameter notifications: центр уведомлений жизненного цикла. Свой у
    ///   теста — потому что в общий `.default` подписаны живые синглтоны
    ///   (`SyncCoordinator` на уход в фон, `PhotoStorageService` на нехватку
    ///   памяти), и тест, постучавший туда, будит половину приложения в чужом
    ///   прогоне — ровно тот класс поломок, про который CLAUDE.md пишет «тест
    ///   роняет ЧУЖОЙ класс».
    static func make(notifications: NotificationCenter = .default) -> FogMetalVeil? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let encoder = FogFrameEncoder(device: device) else { return nil }
        return FogMetalVeil(
            device: device, queue: queue, encoder: encoder, notifications: notifications)
    }

    private let notifications: NotificationCenter

    private init(device: MTLDevice, queue: MTLCommandQueue, encoder: FogFrameEncoder,
                 notifications: NotificationCenter) {
        self.queue = queue
        self.encoder = encoder
        self.notifications = notifications
        super.init(frame: .zero, device: device)

        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        isOpaque = false
        layer.isOpaque = false
        backgroundColor = .clear
        framebufferOnly = true
        // КАДР ЛОЖИТСЯ В ТУ ЖЕ ТРАНЗАКЦИЮ CORE ANIMATION, ЧТО И ДВИЖЕНИЕ
        // КАРТЫ. Без этого `present` асинхронен: мгла показывается тогда,
        // когда её домолотил GPU, а плитки Apple — в коммите CA того же
        // витка главного цикла. Две картинки одного кадра расходятся на
        // один кадр, и на жесте это видно как «туман плывёт за пальцем»
        // (владелец на устройстве, 26 сен). Растровая вуаль этим никогда не
        // болела ровно потому, что везёт свой слой аффинным преобразованием
        // ВНУТРИ `CATransaction` (`FogVeilView.sync`) — то есть уже в том же
        // коммите. Метал получает то же свойство, а `draw(_:)` — тот
        // порядок, которого требует этот режим: `commit` → `waitUntilScheduled`
        // → `drawable.present()`.
        presentsWithTransaction = true
        // Кадр заказываем сами, с `CADisplayLink`: рисовать по расписанию
        // MTKView значит рисовать и на стоящей карте.
        isPaused = true
        enableSetNeedsDisplay = false
        // Жесты обязаны доходить до карты под нами.
        isUserInteractionEnabled = false

        let centre = notifications
        // Уход в фон и возвращение из него — не «полировка жизненного цикла»,
        // а единственное место, где решается, жив ли процесс: работа на GPU
        // из фонового приложения обрывается системой (см. `draw(_:)`).
        centre.addObserver(self, selector: #selector(handleDidEnterBackground),
                           name: UIApplication.didEnterBackgroundNotification, object: nil)
        centre.addObserver(self, selector: #selector(handleWillEnterForeground),
                           name: UIApplication.willEnterForegroundNotification, object: nil)
        centre.addObserver(self, selector: #selector(handleDidBecomeActive),
                           name: UIApplication.didBecomeActiveNotification, object: nil)
        // Текстура покрытия — единственное, что мы держим сверх буферов
        // открытого мира, и единственное, что имеет смысл отдать по нехватке
        // памяти: следующий кадр заводит её заново (спека §8).
        centre.addObserver(self, selector: #selector(handleMemoryWarning),
                           name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) не используется") }

    /// Наблюдатели снимаются явно — не потому что iOS их не снимет сама
    /// (с iOS 9 снимет), а потому что так стоит у соседа (`FogVeilView`), и
    /// расходиться этим двум незачем.
    deinit { notifications.removeObserver(self) }

    // MARK: Жизненный цикл приложения

    /// Ушли в фон: `CADisplayLink` гасим сами. Система его в фоне и так не
    /// тикает, но оставленная ссылка — это тик ровно на возвращении, то есть
    /// кадр РАНЬШЕ, чем приложение снова получило право на GPU.
    @objc private func handleDidEnterBackground() {
        stopTracking()
        forgetFrame()
    }

    /// Возвращаемся: помечаем кадр несуществующим, но НЕ рисуем.
    ///
    /// `willEnterForeground` приходит, пока `applicationState` ещё
    /// `.background` — в `.inactive` он переходит ПОСЛЕ этого уведомления.
    /// Рисовать отсюда значит упереться в собственную защиту из `draw(_:)` и
    /// молча потерять тот самый догоняющий кадр: человек увидел бы голую
    /// карту Apple (растровая вуаль на «Атласе» тумана не рисует) до первого
    /// движения пальцем. Поймано ревью 22 сентября, доккомментарий здесь до
    /// того утверждал обратное.
    @objc private func handleWillEnterForeground() {
        frameDirty = true
        forgetFrame()
    }

    /// Стали активными — вот теперь кадр догоняем. Состояние уже `.active`,
    /// право на GPU есть.
    ///
    /// Лишнего кадра на каждый Центр управления это не стоит: `redrawIfNeeded`
    /// молчит, пока камера та же и ничего не помечено грязным, а после
    /// настоящего ухода в фон помечено (`forgetFrame` выше).
    @objc private func handleDidBecomeActive() {
        redrawIfNeeded()
    }

    /// Памяти не хватает: текстуру покрытия отдаём. Заказывать под нехватку
    /// памяти новый кадр не надо — надо только не считать нарисованным тот,
    /// что на экране: без этого следующий кадр не пришёл бы до первого
    /// движения камеры, и «Атлас» остался бы без тумана.
    @objc private func handleMemoryWarning() {
        coverage = nil
        forgetFrame()
    }

    /// Держим ли мы сейчас текстуру покрытия — для теста: отдача её по
    /// нехватке памяти иначе не наблюдаема ничем.
    var hasCoverageTexture: Bool { coverage != nil }

    /// Кадра на экране больше нет — ни нарисованного, ни «того же самого».
    ///
    /// Зовётся отовсюду, где кадр НЕ СОСТОЯЛСЯ: приложение в фоне, drawable не
    /// выдан, текстуру покрытия отобрали. Обе половины памяти снимаются
    /// вместе, и это не симметрия ради симметрии: `lastRect` — иначе
    /// `redrawIfNeeded` посчитает эту камеру уже нарисованной, `restFrameDrawn`
    /// — иначе смена темы или съехавшее окно атрибуции на СТОЯЩЕЙ карте
    /// пропадут насовсем, до первого движения пальца.
    private func forgetFrame() {
        lastRect = nil
        restFrameDrawn = false
    }

    // MARK: Данные

    /// Открытый мир. Буферы собираются вне главного потока и подменяются
    /// целиком — дозаписи в живой буфер нет: кадр может идти прямо сейчас.
    /// Квантование открытого клетками. Кадра НЕ заказывает — его заказывает
    /// тот, кто поставил вид карты ЦЕЛИКОМ.
    ///
    /// Стиль это две вещи сразу: палитра (общая `FogVeilPainter.palette`) и
    /// клетки. Пока кадр заказывали порознь — `applyPalette` своим
    /// `invalidate()`, а этот метод вторым, — между двумя заказами
    /// существовал кадр, которого нет ни в одном стиле: ночная мгла С
    /// клетками или светлая БЕЗ них. Именно он и оставался на экране:
    /// второй заказ на той же камере до экрана не доезжает (владелец на
    /// устройстве 27 сентября, два кадра подряд — «переключая с „клетки“ на
    /// „ночь“ карта показывает ночную карту, но с клетками»). «Туман» этим
    /// не болел, потому что там меняется только одна половина.
    ///
    /// Что смена клеток доедет до СТОЯЩЕЙ карты, держит не этот зов, а ключ
    /// латча в `invalidate()` (`drawnUsesCells`).
    func setUsesCells(_ enabled: Bool) {
        usesCells = enabled
    }

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
                self.meshBuilds += 1
                self.frameDirty = true
                self.restFrameDrawn = false
                self.redrawIfNeeded()
            }
        }
    }

    // MARK: Прорезь у машины на живой записи

    /// Где и насколько раскрыт туман вокруг машины прямо сейчас — в ЗЕМНЫХ
    /// координатах: карта на записи едет сама, и точка экрана устарела бы к
    /// следующему кадру.
    private var liveReveal: (coordinate: CLLocationCoordinate2D,
                             progress: Double, metres: Double)?

    /// Прорезь у машины: «туман выгорает по новому пути».
    ///
    /// Стоит она двух чисел в буфере кадра и НИ ОДНОЙ пересборки буферов
    /// открытого мира: дыру считает сам фрагментный шейдер по расстоянию до
    /// середины (`FogRevealCircle`). У растровой вуали здесь маска на слое, и
    /// не от хорошей жизни — там «перерисовать» значит собрать
    /// восьмимегабайтную картинку, а прорезь растёт шестьдесят раз в секунду
    /// (`FogRevealAnimation`, 0.7 с).
    ///
    /// Кадр она заказывает КАЖДЫЙ — камера при этом может стоять, и без
    /// `frameDirty` дыра осталась бы того же размера, каким её застало
    /// последнее движение карты.
    ///
    /// После финиша коридор по-настоящему прожигает слой открытого
    /// (`RevealedLayerStore`), новый слой приходит с ним, и прорезь снимается
    /// тем же `nil`, которым её завёл `MapViewModel.rebuildFog`.
    /// - Parameter metres: радиус на полном раскрытии. Параметром, а не
    ///   константой внутри, по той же причине, что у `FogVeilView.setReveal`:
    ///   у машины он свой, и сведённые в одно число они разъехались бы при
    ///   первой правке любого из двух.
    func setLiveReveal(coordinate: CLLocationCoordinate2D?, progress: Double,
                       metres: Double = FogVeilRenderer.revealMetres) {
        guard let coordinate, progress > 0 else {
            guard liveReveal != nil else { return }
            liveReveal = nil
            orderRevealFrame()
            return
        }
        liveReveal = (coordinate, progress, metres)
        orderRevealFrame()
    }

    /// Стоит ли сейчас прорезь — для теста.
    var hasLiveReveal: Bool { liveReveal != nil }

    /// Кадр под новую прорезь. Латч покоя снимается вместе с заказом: на
    /// экране лежит картинка, которой там уже нет, и следующая смена темы
    /// обязана доехать.
    private func orderRevealFrame() {
        frameDirty = true
        restFrameDrawn = false
        redrawIfNeeded()
    }

    /// Прорезь в ТОЧКАХ экрана на этом кадре. `nil` — прорези нет.
    ///
    /// Считается на каждом кадре и по той же арифметике, что у растровой маски
    /// (`FogVeilView.positionLiveReveal`): карта под прорезью едет, а сама
    /// прорезь привязана к земле.
    private func revealCircle(map: MKMapView) -> FogRevealCircle? {
        guard let live = liveReveal else { return nil }
        let metresPerPoint = map.metersPerScreenPoint
        guard metresPerPoint > 0, metresPerPoint.isFinite else { return nil }
        let radius = CGFloat(live.metres * live.progress / metresPerPoint)
        return FogRevealCircle(centre: map.convert(live.coordinate, toPointTo: self),
                               radius: max(radius, 1))
    }

    // MARK: Жизнь

    /// Запоминает карту и рисует ОДИН кадр. `CADisplayLink` здесь не
    /// заводится: пока карта стоит, каждый его тик спрашивал бы у неё три
    /// `convert` и выбрасывал ответ — сто двадцать раз в секунду всё время,
    /// что открыт «Атлас». Тиками командует хост из делегата карты, теми же
    /// вызовами, что и растровой вуалью.
    func attach(map: MKMapView) {
        self.map = map
        frameDirty = true
        restFrameDrawn = false
        redrawIfNeeded()
    }

    func detach() {
        stopTracking()
        map = nil
        coverage = nil
        // Прорезь — состояние одной секунды записи, и пережить уход экрана она
        // не имеет права: вернувшись, карта нарисовала бы дыру там, где машины
        // давно нет. Сам кадр здесь не заказывается — рисовать некуда.
        liveReveal = nil
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

    /// Карта СООБЩИЛА новую камеру — рисуем кадр прямо сейчас.
    ///
    /// Зовётся из `mapViewDidChangeVisibleRegion`, то есть в тот самый виток
    /// главного цикла, в котором MapKit обновил свою камеру, и в ту же
    /// транзакцию Core Animation, в которой поедут его плитки. До этого кадр
    /// заказывал ТОЛЬКО `CADisplayLink`, а его тик и обновление камеры —
    /// два разных момента кадра: мгла рисовалась по камере, которая уже
    /// устарела, и на жесте это видно как «туман плывёт за пальцем»
    /// (владелец на устройстве, 26 сен; `presentsWithTransaction` этого не
    /// лечит — он про то, КОГДА показать кадр, а не про то, КАКУЮ камеру в
    /// него положить). `CADisplayLink` остаётся: он догоняет движения, о
    /// которых карта не сообщает покадрово, а лишней работы не делает —
    /// `redrawIfNeeded` выходит сразу, если камера та же.
    func followCamera() { redrawIfNeeded() }

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
        if drawnPaletteIsDark != FogVeilPainter.palette.isDark || drawnCarve != carve
            || drawnUsesCells != usesCells {
            restFrameDrawn = false
        }
        guard !restFrameDrawn else { return }
        restFrameDrawn = true
        frameDirty = true
        redrawIfNeeded()
    }

    /// Окно под подписью Apple Maps — то же, что у растровой вуали, и теми же
    /// числами (`AttributionCarve`). Мгла под ним ПРИГЛУШАЕТСЯ до половины
    /// силы, а не снимается: полное снятие вскрывало дневную карту «Атласа» и
    /// читалось плашкой (задача A2, 21 сентября).
    ///
    /// Зовётся на каждом проходе разметки, поэтому тем же окном молчит: кадр
    /// заказывает `invalidate()`, а тот сверяется с окном последнего кадра.
    func setAttributionCarve(_ rect: CGRect?) {
        carve = rect.map(FogCarveWindow.attribution(rect:))
        invalidate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        frameDirty = true
        restFrameDrawn = false
        redrawIfNeeded()
    }

    // MARK: Кадр

    /// Кадр рисуется только если камера сдвинулась или сменились данные.
    private func redrawIfNeeded() {
        guard let map, bounds.width > 1, bounds.height > 1 else { return }
        let rect = map.visibleMapRect
        let corners = Self.corners(of: rect, map: map, in: self)
        if !frameDirty, let last = lastRect, Self.sameRect(last, rect), corners == lastCorners {
            return
        }
        lastRect = rect
        lastCorners = corners
        frameDirty = false
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
    /// рисовать» и есть то, что меряет `frames`, — иначе вид, которому не
    /// выдали drawable, выглядел бы для тестов покоя вечно спящим.
    override func draw(_ rect: CGRect) {
        // В ФОНЕ GPU НЕ ТРОГАЕМ ВОВСЕ, и это про жизнь процесса, а не про
        // экономию: `present`/`commit` из фонового приложения — это IOAF
        // «Insufficient Permission (to submit GPU work from background)» и
        // убитое системой приложение. TripTrack живёт в фоне часами на
        // геолокации, и дорога сюда короткая: поездка финишировала в кармане
        // → `.revealedLayerChanged` → перезагрузка вью-модели →
        // `updateUIViewController` → `setLayer` → кадр. Взяться за него мы
        // даже не взялись, поэтому `frames` не растёт, — а сам кадр
        // ЗАБЫВАЕТСЯ: вернувшись, экран обязан нарисовать его заново.
        guard !isBackgrounded() else { forgetFrame(); return }
        frames += 1
        drawnPaletteIsDark = FogVeilPainter.palette.isDark
        drawnCarve = carve
        drawnUsesCells = usesCells
        // Рисовать нечем (вид только что встал в дерево, drawable не выдан) —
        // кадр пропускаем, но ПАМЯТЬ о нём стираем целиком: иначе
        // `redrawIfNeeded` посчитал бы камеру нарисованной, а `invalidate()`
        // — заказ выполненным, и смена темы на стоящей карте пропала бы
        // насовсем.
        guard let map, let device, let drawable = currentDrawable,
              let pass = currentRenderPassDescriptor,
              let buffer = queue.makeCommandBuffer() else { forgetFrame(); return }
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
            palette: FogVeilPainter.palette,
            carve: carve,
            reveal: revealCircle(map: map),
            grid: usesCells
                ? FogCellGrid.make(visible: visible, viewportPoints: bounds.size)
                : nil)

        // Текстура покрытия пережила прошлый кадр — её не стало только если
        // сменился размер или память отобрали. Не создалась вовсе — кадр
        // выходит пустым, но `present` всё равно нужен: иначе drawable
        // остался бы у нас на руках.
        if let coverage = coverageTexture(device: device) {
            encoder.encode(mesh: mesh, params: params, coverage: coverage,
                           target: pass, into: buffer)
        }

        // Цена КОДИРОВАНИЯ снимается здесь, до отправки: ниже идёт ожидание
        // планировщика GPU, и, попав в ту же сумму, оно превратило бы
        // «кодирование, мс/кадр» в другое число и сломало бы сравнение с
        // бюджетом.
        encodeSeconds += CACurrentMediaTime() - started
        // Порядок продиктован `presentsWithTransaction` (см. `init`): при нём
        // presentation делает САМ drawable и делает синхронно, уже после того
        // как буфер отдан планировщику. `buffer.present(drawable)` в этом
        // режиме показал бы кадр мимо транзакции — то есть вернул бы ровно ту
        // рассинхронизацию, ради которой всё это и заведено.
        buffer.commit()
        buffer.waitUntilScheduled()
        drawable.present()
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
