import MapKit
import UIKit
import os

/// Посадка Metal-тумана в дерево карты — одна на три карты.
///
/// Своего поиска по именам приватных классов у Metal-слоя НЕТ и быть не
/// должно: дерево `MKMapView` знает `FogVeilView.attach(inside:)`, и второй
/// код, который знал бы его же, разъехался бы с первым на следующей iOS.
/// Metal-слой просто садится в ТОТ ЖЕ родитель, что нашла растровая вуаль, и
/// НИЖЕ её — сверху у вуали остаются векторные слои (жилка сети и выбранный
/// маршрут), а на экране поездки и записи выше лежит ещё и сам маршрут,
/// который рисует `MKOverlayRenderer`.
///
/// Тип появился, когда карт стало три. На «Атласе» этот порядок действий жил
/// внутри `MapHostController`, и перенести его в координаторы экрана поездки и
/// экрана записи значило бы написать его во второй и третий раз — то есть
/// завести три места, где чинить одну и ту же находку ревью («слой вылетел из
/// дерева, а плиточные оверлеи сняты — карта осталась без тумана вовсе»).
/// Различаются три зова только параметрами.
@MainActor
final class FogMetalSeat {
    private static let log = Logger(subsystem: "com.onezee.TripTrack", category: "fogmetal")
    /// О недоступном Metal говорим ОДИН раз за запуск, а не по разу на карту:
    /// строка отвечает на вопрос «почему туман растровый», и ответ у трёх карт
    /// один и тот же.
    private static var loggedUnavailable = false

    /// `nil` — Metal на этом устройстве недоступен или выключатель снят: карта
    /// целиком возвращается к растровой вуали 0.7.0. Обе дороги ведут в одно
    /// место нарочно, второго пути отката не заводится.
    let veil: FogMetalVeil?

    /// Пересадка идёт прямо сейчас: она трогает дерево, а дерево зовёт
    /// разметку — то есть эту же проверку изнутри неё самой. Тот же приём, что
    /// у `FogVeilView.verifySeating`.
    private var reseating = false

    /// Слой сел в дерево. «Атлас» отдаёт этим окно под подписью Apple: гнездо
    /// теряется и возвращается по нескольку раз за жизнь экрана, а прохода
    /// разметки за этим может и не случиться.
    var onSeated: (() -> Void)?

    /// Сидит ли слой в дереве. `false` — тиков ему заказывать незачем: рисовать
    /// он будет в пустоту.
    private(set) var isSeated = false

    init() {
        veil = FogMetalAvailability.isActive ? FogMetalVeil.make() : nil
        if FogMetalAvailability.isActive, veil == nil, !Self.loggedUnavailable {
            Self.loggedUnavailable = true
            Self.log.notice("metal-туман недоступен, карты на растре")
        }
    }

    /// Рисует ли туман Metal. Этим же числом растровая вуаль переводится в
    /// `vectorOnly`: мглу рисует GPU, вуали остаётся её вектор.
    var isActive: Bool { veil != nil }

    // MARK: Дерево

    /// Сесть под растровую вуаль — или пересесть, если место потеряно.
    ///
    /// Идемпотентно и зовётся из трёх мест: с посадки самой вуали
    /// (`VeilSeat.onAttached`), с каждого прохода разметки и с каждой посадки
    /// карты (`updateUIView` приходит на каждый кадр реплея). Одна дверь на
    /// «сесть впервые» и «вернуться» нарочно: `FogVeilView.verifySeating`
    /// возвращает в дерево СЕБЯ и, вернувшись удачно, молчит — о пересборке
    /// сабвью MapKit Metal-слою не сказал бы никто, и карта показывала бы
    /// ГОЛУЮ карту Apple (растра у вуали нет, плиточные оверлеи сняты).
    func follow(_ seat: VeilSeat, on map: MKMapView) {
        guard let veil, seat.isAttached, !reseating,
              Self.needsReseating(metal: veil, veil: seat.veil),
              let parent = seat.veil.superview else { return }
        reseating = true
        defer { reseating = false }
        // Снятие делает «сядем заново» одинаковым для обоих случаев —
        // вылетевшего из дерева и просто всплывшего поверх вуали.
        veil.removeFromSuperview()
        veil.frame = parent.bounds
        veil.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        parent.insertSubview(veil, belowSubview: seat.veil)
        veil.attach(map: map)
        isSeated = true
        onSeated?()
    }

    /// Только снимает. Ничего, что относится к настройке слоя, здесь быть не
    /// должно: гнездо теряется и возвращается по нескольку раз за жизнь
    /// экрана, а настраивается слой один раз.
    func unseat() {
        isSeated = false
        veil?.detach()
        veil?.removeFromSuperview()
    }

    /// Сидит ли Metal-слой на своём месте: в том же родителе, что растровая
    /// вуаль, и НИЖЕ её.
    ///
    /// Чистая — потому что живое дерево MapKit в тесте не построить, а вопрос
    /// здесь арифметический: два `firstIndex` и сравнение родителей.
    ///
    /// Вуаль без родителя — это «не сейчас», а не «пересадить». Место в дереве
    /// ищет она, и пока она сама не вернулась, Metal-слою садиться не подо
    /// что; спросят снова следующим проходом разметки.
    static func needsReseating(metal: UIView?, veil: UIView) -> Bool {
        guard let metal, let parent = veil.superview else { return false }
        guard metal.superview === parent,
              let mine = parent.subviews.firstIndex(of: metal),
              let theirs = parent.subviews.firstIndex(of: veil),
              mine < theirs else { return true }
        return false
    }

    // MARK: Прокладки к слою

    /// Открытый мир. Зовётся рядом с `setLayer` растровой вуали — два
    /// получателя одного слоя обязаны быть видны в одной строке.
    func setLayer(_ layer: RevealedLayer) {
        veil?.setLayer(layer)
    }

    func invalidate() {
        guard isSeated else { return }
        veil?.invalidate()
    }

    /// Камера тронулась. В покое тиков нет вовсе — поэтому заводит их делегат
    /// карты, теми же тремя местами, что и у растровой вуали.
    func startTracking(tail: TimeInterval = FogMetalVeil.trackingTail) {
        guard isSeated else { return }
        veil?.startTracking(tail: tail)
    }

    /// Карта сообщила новую камеру — кадр рисуется СЕЙЧАС, в этом же витке
    /// главного цикла. Подробности и цена — у `FogMetalVeil.followCamera`.
    func followCamera() {
        guard isSeated else { return }
        veil?.followCamera()
    }

    /// Камера встала: досмотреть хвост и погаснуть. Заказывать чёткий кадр,
    /// как растровой вуали, металу нечего — он и так рисует каждый кадр.
    func extendTracking(tail: TimeInterval = FogMetalVeil.trackingTail) {
        guard isSeated else { return }
        veil?.extendTracking(tail: tail)
    }

    /// Окно под подписью Apple в координатах САМОГО слоя.
    ///
    /// Сегодня он сосед вуали с тем же `frame`, то есть числа совпадают, — но
    /// это наблюдение, а не контракт: место в дереве ищет `VeilSeat`, и
    /// спросить UIKit стоит дешевле, чем однажды поймать окно, съехавшее на
    /// высоту статус-бара.
    func setAttributionCarve(_ rect: CGRect?, from space: UIView) {
        guard let veil else { return }
        veil.setAttributionCarve(rect.map { veil.convert($0, from: space) })
    }

    /// Прорезь у машины на живой записи. Два числа на кадр — считает её сам
    /// шейдер (`FogRevealCircle`), поэтому ни кадра растра, ни пересборки
    /// буферов она не стоит.
    func setLiveReveal(coordinate: CLLocationCoordinate2D?, progress: Double) {
        veil?.setLiveReveal(coordinate: coordinate, progress: progress)
    }
}
