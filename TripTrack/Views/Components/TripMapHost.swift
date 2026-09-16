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
/// Владелец хоста — экран поездки (`@StateObject`). Уходя, он обязан позвать
/// `tearDown()`: `dismantleUIView` у карты с хостом ничего не снимает (иначе
/// переезд между героем и полным экраном каждый раз ронял бы вуаль), и без
/// этого вызова за кадром остались бы два растра и `CADisplayLink`.
@MainActor
final class TripMapHost: ObservableObject {
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

    /// Последний кадр карты, снятый перед тем, как она уехала на полный
    /// экран. Слот героя показывает его, пока карты в нём нет: пустой
    /// прямоугольник на месте карты — это моргание, которое видно.
    @Published private(set) var snapshot: UIImage?

    /// Отдать готовую карту или создать первую.
    ///
    /// `removeFromSuperview` перед возвратом — не осторожность, а порядок:
    /// SwiftUI кладёт результат `makeUIView` в СВОЙ контейнер, и карта,
    /// оставшаяся подпиской в прежнем, приехала бы туда вместе со старым
    /// расположением.
    func map(orMake make: () -> MKMapView) -> MKMapView {
        if let mapView {
            mapView.removeFromSuperview()
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
        coordinator?.isHosted = false
        coordinator?.veilSeat?.detach()
        mapView?.removeFromSuperview()
        mapView = nil
        coordinator = nil
        snapshot = nil
    }
}
