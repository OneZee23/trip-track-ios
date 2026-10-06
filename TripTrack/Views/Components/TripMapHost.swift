import SwiftUI
import MapKit

/// Карта поездки, живущая ДОЛЬШЕ любого её представления.
///
/// До 0.7.0 полноэкранная карта была отдельным `.fullScreenCover`, и это
/// значило вторую `MKMapView` целиком: разрез маршрута по скорости, оверлеи,
/// точки старта и финиша, растрирование картинок аннотаций — и сверху
/// посадка вуали с первым растром тумана. Всё это считалось за системной
/// шторкой, которая к тому моменту уже ехала снизу вверх, и заход на полный
/// экран получался тяжёлым — жалоба владельца на устройстве.
///
/// Здесь карта одна. Хост держит её и её координатора между двумя
/// представлениями — героем на экране поездки и полноэкранной раскладкой, —
/// а `RouteMapView` с непустым `host` не создаёт карту заново, а забирает
/// готовую. Вуаль при этом НЕ пересаживается: место в дереве проверяет
/// `VeilSeat.verifySeating` на каждом `updateUIView`, и переезд карты из
/// одного контейнера в другой она переживает сама.
///
/// Владелец хоста — экран поездки (`@StateObject`). Уходит он не по
/// `.onDisappear` (тот приходит и на ПУШ чужого экрана поверх), а по счётчику
/// смонтированных представлений: `retain()` из `makeUIView`, `release()` из
/// `dismantleUIView`. Ноль представлений — экрана больше нет, и вуаль с карты
/// снимается здесь и только здесь.
@MainActor
final class TripMapHost: ObservableObject {
    enum Presentation { case hero, fullscreen }

    /// Меняется действием экрана ДО SwiftUI-фазы, поэтому старое значение
    /// representable не может забрать карту после смены презентации.
    var activePresentation: Presentation = .hero
    private weak var heroSlot: TripMapSlotView?
    private weak var fullscreenSlot: TripMapSlotView?

    func register(_ slot: TripMapSlotView, for presentation: Presentation) {
        switch presentation {
        case .hero: heroSlot = slot
        case .fullscreen: fullscreenSlot = slot
        }
    }

    func canClaim(_ slot: TripMapSlotView, for presentation: Presentation) -> Bool {
        guard presentation == activePresentation else { return false }
        switch presentation {
        case .hero: return heroSlot === slot
        case .fullscreen: return fullscreenSlot === slot
        }
    }

    func unregister(_ slot: TripMapSlotView) {
        if heroSlot === slot { heroSlot = nil }
        if fullscreenSlot === slot { fullscreenSlot = nil }
    }

    /// Сама карта. `nil` — ещё не создавалась.
    private(set) var mapView: MKMapView?
    /// Делегат и вся память карты (оверлеи, отметки, посадка вуали).
    private(set) var coordinator: RouteMapView.Coordinator?

    /// Сколько раз карта была СОЗДАНА за жизнь хоста.
    ///
    /// Не диагностика: ровно это число и есть предмет всей работы — заход на
    /// полный экран обязан оставить его равным единице. Держит
    /// `TripMapHostTests`.
    private(set) var creationCount = 0

    /// Сколько представлений сейчас держат эту карту.
    ///
    /// `.onDisappear` экрана единственной дверью быть не мог: в
    /// `NavigationStack` он приходит и тогда, когда экран поездки просто
    /// НАКРЫЛИ сверху — паспортом машины, чужим профилем, путешествием,
    /// экраном места. Карту при этом рвать нельзя: возврат застал бы
    /// `host.mapView == nil` при живом представлении героя, и следующее
    /// раскрытие построило бы ВТОРУЮ `MKMapView` со второй вуалью и вторым
    /// `CADisplayLink` — ровно та поломка, ради которой хост и написан.
    ///
    /// Считаем то, что считается честно: `makeUIView` берёт, `dismantleUIView`
    /// отдаёт. Пуш не трогает ни того, ни другого.
    private(set) var mounted = 0
    private var teardownTask: Task<Void, Never>?

    /// Последний кадр карты, снятый перед тем, как она уехала на полный
    /// экран. Слот героя показывает его, пока карты в нём нет: пустой
    /// прямоугольник на месте карты — это моргание, которое видно.
    @Published private(set) var snapshot: UIImage?
    /// First fully drawn, fitted viewport. Latched for this map's lifetime:
    /// fullscreen transfer, later pans and a return must not flash a loader.
    @Published private(set) var hasRenderedRoute = false

    func didRenderRoute(on map: MKMapView) {
        guard map === mapView, !hasRenderedRoute else { return }
        hasRenderedRoute = true
    }

    /// Представление смонтировано. Зовёт `RouteMapView.makeUIView`.
    func retain() {
        mounted += 1
        teardownTask?.cancel()
        teardownTask = nil
    }

    /// Представление снято. Зовёт `RouteMapView.dismantleUIView`.
    ///
    /// Разрыв откладывается на следующий виток главного актёра НАРОЧНО:
    /// переезд карты между слотом героя и полноэкранным слоем — это всегда
    /// «сняли одно, поставили другое», и порядок этих двух вызовов SwiftUI не
    /// обещает. Ноль, доживший до следующего витка, — настоящий.
    func release() {
        mounted = max(0, mounted - 1)
        guard mounted == 0 else { return }
        teardownTask?.cancel()
        teardownTask = Task { @MainActor [weak self] in
            guard let self, self.mounted == 0, !Task.isCancelled else { return }
            self.tearDown()
        }
    }

    /// Отдать готовую карту или создать первую. Передачу между видами
    /// выполняет слот, когда у него есть и карта, и прежний владелец.
    func map(orMake make: () -> MKMapView) -> MKMapView {
        if let mapView {
            // Переносом владеет TripMapSlotView.adopt: ему нужен прежний
            // слот, чтобы отозвать его право на карту до нового layout.
            // SwiftUI владеет слотом, а не этой MKMapView.
            return mapView
        }
        let created = make()
        creationCount += 1
        mapView = created
        return created
    }

    /// Отдать координатора или запомнить нового.
    func coordinator(orMake make: () -> RouteMapView.Coordinator) -> RouteMapView.Coordinator {
        if let coordinator { return coordinator }
        let created = make()
        created.isHosted = true
        coordinator = created
        return created
    }

    /// Последний рубеж.
    ///
    /// Обычный выход — счётчик (`release()`), запасной — карта, не вернувшаяся
    /// в окно (`VeilHostMapView.onWindowChange`). Но `dismantleUIView` SwiftUI
    /// вправе придержать, а окно у придержанной карты может и не обнулиться;
    /// хост в этот момент уже никому не нужен и освобождается. Вуаль с её
    /// `CADisplayLink` и двумя растрами за кадром не живёт.
    ///
    /// `deinit` не изолирован, поэтому снятие уезжает на главный актёр
    /// задачей; `self` в неё НЕ попадает — только сама посадка.
    deinit {
        guard let seat = coordinator?.veilSeat else { return }
        Task { @MainActor in seat.detach() }
    }

    /// Снять кадр карты — для слота героя на время переезда.
    ///
    /// `drawHierarchy`, а не `layer.render(in:)`: содержимое `MKMapView`
    /// рисуется не нашим процессом, и слой отдаёт пустоту. `afterScreenUpdates:
    /// false` — берём то, что УЖЕ на экране: `true` заставляет систему
    /// прогнать полный цикл отрисовки синхронно, а мы стоим ровно в той
    /// секунде, ради которой всё и затевалось.
    func captureSnapshot() {
        guard let mapView, mapView.bounds.width > 1, mapView.bounds.height > 1 else { return }
        let renderer = UIGraphicsImageRenderer(bounds: mapView.bounds)
        snapshot = renderer.image { _ in
            mapView.drawHierarchy(in: mapView.bounds, afterScreenUpdates: false)
        }
    }

    func clearSnapshot() {
        snapshot = nil
    }

    /// Экран уходит. Здесь, и только здесь, вуаль снимается с карты.
    func tearDown() {
        teardownTask?.cancel()
        teardownTask = nil
        mounted = 0
        coordinator?.isHosted = false
        coordinator?.veilSeat?.detach()
        heroSlot = nil
        fullscreenSlot = nil
        mapView?.removeFromSuperview()
        mapView = nil
        coordinator = nil
        snapshot = nil
        hasRenderedRoute = false
    }
}
