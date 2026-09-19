import UIKit
import MapKit

/// Посадка экранной вуали в дерево карты — одна на три карты.
///
/// Вуаль (`FogVeilView`) ничего не знает ни про «Атлас», ни про экран поездки,
/// ни про экран записи; всё, что у них общего, — порядок действий вокруг неё:
/// встать в дерево (не с первой попытки — контейнеры MapKit появляются позже
/// первого кадра), сказать карте снять плиточные оверлеи, вести привязку, а на
/// уходе экрана уйти вместе с ним. Этот порядок и живёт здесь.
///
/// Второй копии этого кода в проекте быть не должно: на «Атласе» он уже стоил
/// одной находки ревью («вуаль вылетела из дерева, а оверлеи сняты — карта
/// осталась без тумана вовсе»), и повторить её на двух других картах было бы
/// повторением по буквам.
@MainActor
final class VeilSeat {
    /// Сколько раз пробуем встать. Контейнеры аннотаций и оверлеев появляются
    /// в дереве не обязательно к первому кадру — а падать из-за этого нельзя.
    static let maxTries = 25
    static let retryDelay: TimeInterval = 0.2

    let veil: FogVeilView
    /// Куда именно эта карта сажает вуаль. Читается тестом: у трёх карт места
    /// разные, и перепутать их — значит либо спрятать поездку под туманом,
    /// либо нарисовать туман дважды.
    let placement: FogVeilView.Seat
    private weak var map: MKMapView?
    private var tries = 0
    private var retrying = false

    /// Вуаль встала: плиточные оверлеи тумана надо снять с карты, иначе одно и
    /// то же рисуется дважды, а нижнее не видно.
    var onAttached: (() -> Void)?
    /// Вуаль ушла (экран закрылся или она потеряла место): оверлеи вернуть,
    /// иначе тумана не останется вовсе.
    var onDetached: (() -> Void)?

    private(set) var isAttached = false

    init(margin: Double, seat: FogVeilView.Seat) {
        self.veil = FogVeilView(margin: margin)
        self.placement = seat
        veil.onLostFromHierarchy = { [weak self] in self?.standDown() }
    }

    /// Встроиться в эту карту. Идемпотентно: зовётся и из жизненного цикла, и
    /// из `updateUIView`, который приходит на каждый кадр реплея.
    func attach(to map: MKMapView) {
        if self.map !== map {
            self.map = map
            tries = 0
        }
        guard !isAttached else {
            // Уже сидим — но, может быть, уже НЕ там: MapKit вправе пересобрать
            // сабвью при неподвижной карте, а привязка проверяет место только
            // под `CADisplayLink`, то есть в покое не проверяет никто.
            veil.verifySeating()
            return
        }
        guard tries < Self.maxTries else { return }
        tryAttach()
    }

    private func tryAttach() {
        guard !isAttached, let map else { return }
        tries += 1
        if veil.attach(inside: map, map: map, seat: placement) {
            isAttached = true
            onAttached?()
            return
        }
        guard tries < Self.maxTries, !retrying else { return }
        retrying = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelay) { [weak self] in
            guard let self else { return }
            self.retrying = false
            self.tryAttach()
        }
    }

    /// Экран ушёл — вуаль уходит с ним: восемь мегабайт растра и
    /// `CADisplayLink` за кадром не живут.
    func detach() {
        guard isAttached else { return }
        standDown()
    }

    /// Снять вуаль и вернуть туман плиточному рендереру. Общая концовка для
    /// двух поводов — экран закрылся и вуаль потеряла место в дереве, — потому
    /// что делать в обоих надо ровно одно и то же.
    private func standDown() {
        let was = isAttached
        isAttached = false
        tries = 0
        veil.detach()
        if was { onDetached?() }
    }

    // MARK: Прокладки к вуали

    func invalidate() {
        guard isAttached else { return }
        veil.invalidate()
    }

    func startTracking(tail: TimeInterval = FogVeilView.trackingTail) {
        guard isAttached else { return }
        veil.startTracking(tail: tail)
    }

    func extendTracking(tail: TimeInterval = FogVeilView.trackingTail) {
        guard isAttached else { return }
        veil.extendTracking(tail: tail)
    }

    /// Камера встала: привязка и один ЧЁТКИЙ кадр под новый масштаб.
    func settle(on map: MKMapView, tail: TimeInterval = 0.6) {
        guard isAttached else { return }
        veil.extendTracking(tail: tail)
        veil.sync(map: map)
        veil.maybeRender(map: map, settled: true)
    }
}

/// Карта, которая сообщает о своём появлении в окне и уходе из него.
///
/// У `UIViewRepresentable` нет вью-контроллера, а вуаль обязана уйти вместе с
/// экраном: иначе `CADisplayLink` и два растра переживут закрытие листа. На
/// «Атласе» тот же вопрос решает `MapHostController`, у которого
/// `viewWillDisappear` есть.
final class VeilHostMapView: MKMapView {
    var onWindowChange: ((UIWindow?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window)
    }
}
