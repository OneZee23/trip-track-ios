import MapKit
import SwiftUI

/// Карта, на которой человек СТАВИТ дом пальцем (0.8.2).
///
/// Своя маленькая карта, а не `PlacesMapView` и не карта «Атласа»: здесь один
/// вопрос — «где твой дом» — и одно действие, тап. Тащить сюда карту «Атласа»
/// значило бы привести вместе с ней туман, жилку, булавки мест и подписи
/// регионов, то есть всё, что на этот вопрос не отвечает.
///
/// Круг зоны рисуется ИМЕННО ЗДЕСЬ и только здесь. На «Атласе» его нет
/// нарочно: там мгла рисуется поверх карты (Metal-вуаль 0.8.0), и оверлей
/// круга лёг бы под неё — человек увидел бы то ли круг, то ли нет, в
/// зависимости от стиля карты. Радиус выбирают здесь, и обратная связь на
/// выбор нужна здесь же.
struct HomePickerMapView: UIViewRepresentable {
    /// Дом. `nil` — ещё не поставлен, карта пустая.
    let home: CLLocationCoordinate2D?
    /// Куда смотреть, пока дома нет.
    ///
    /// Без этого карта открывается НА ВЕСЬ МИР, и «нажмите на карту, чтобы
    /// поставить дом» означает поставить его с точностью до тысячи
    /// километров — поймано первым же кадром на симуляторе. Порядок такой:
    /// живое положение (его приносит сама карта, см. `didUpdate`), иначе эта
    /// подсказка от экрана, иначе мир.
    var fallback: CLLocationCoordinate2D?
    /// Радиус зоны в метрах. Круг рисуется всегда, когда есть дом: он
    /// показывает, что именно выбрал человек, ещё до включения тумблера.
    let radius: Double
    let onPlace: (CLLocationCoordinate2D) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.pointOfInterestFilter = .excludingAll
        // Наклон выключен по той же причине, что и на трёх других картах:
        // перспектива здесь ничего не объясняет, а промахнуться пальцем
        // помогает.
        map.isPitchEnabled = false
        map.register(HomePinView.self, forAnnotationViewWithReuseIdentifier: HomePinView.reuseID)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        map.addGestureRecognizer(tap)
        context.coordinator.map = map

        if let start = home ?? fallback {
            map.setRegion(MKCoordinateRegion(center: start,
                                             latitudinalMeters: radius * 6,
                                             longitudinalMeters: radius * 6),
                          animated: false)
            context.coordinator.didFrame = true
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.onPlace = onPlace
        context.coordinator.radius = radius
        context.coordinator.sync(home: home, radius: radius, on: map)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPlace: onPlace) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onPlace: (CLLocationCoordinate2D) -> Void
        weak var map: MKMapView?
        private var placed: CLLocationCoordinate2D?
        private var placedRadius: Double = 0
        /// Первый показ уже поставленного дома камеру двигать не должен
        /// дважды — `makeUIView` это уже сделал.
        var didFrame = false
        /// Радиус нужен и тут: на живое положение карта наводится тем же
        /// масштабом, что и на дом.
        var radius: Double = 500

        init(onPlace: @escaping (CLLocationCoordinate2D) -> Void) {
            self.onPlace = onPlace
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let map else { return }
            let point = gesture.location(in: map)
            onPlace(map.convert(point, toCoordinateFrom: map))
            Haptics.tap()
        }

        func sync(home: CLLocationCoordinate2D?, radius: Double, on map: MKMapView) {
            let moved = home.map { $0.latitude != placed?.latitude || $0.longitude != placed?.longitude }
                ?? (placed != nil)
            guard moved || radius != placedRadius else { return }
            placed = home
            placedRadius = radius

            map.removeAnnotations(map.annotations.filter { $0 is HomeAnnotation })
            map.removeOverlays(map.overlays.filter { $0 is MKCircle })
            guard let home else { return }
            map.addAnnotation(HomeAnnotation(coordinate: home))
            map.addOverlay(MKCircle(center: home, radius: radius))

            if !didFrame {
                didFrame = true
            } else if moved {
                // Камера едет только за ПЕРЕЕЗДОМ дома, не за сменой радиуса:
                // человек выбирает радиус, глядя на круг, и уезжающая под
                // пальцем карта отвечала бы не на тот вопрос.
                map.setCenter(home, animated: true)
            }
        }

        /// Живое положение приходит позже первого кадра, и, пока дома нет,
        /// оно и есть лучший ответ на «где ты живёшь». Наводимся ОДИН раз:
        /// карта, которая едет под пальцем на каждое обновление GPS, ставить
        /// точку не даёт.
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard !didFrame, placed == nil, let live = userLocation.location else { return }
            didFrame = true
            mapView.setRegion(MKCoordinateRegion(center: live.coordinate,
                                                 latitudinalMeters: radius * 6,
                                                 longitudinalMeters: radius * 6),
                              animated: true)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let circle = overlay as? MKCircle else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKCircleRenderer(circle: circle)
            renderer.fillColor = UIColor(AtlasTheme.accent).withAlphaComponent(0.16)
            renderer.strokeColor = UIColor(AtlasTheme.accent).withAlphaComponent(0.7)
            renderer.lineWidth = 2
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is HomeAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: HomePinView.reuseID, for: annotation)
            // Та же метка, но ДРУГАЯ цель: здесь она показывает выбранную
            // точку, а на «Атласе» открывает карточку. Одно имя на двоих
            // однажды уже увело тест не туда.
            view.accessibilityIdentifier = "home_pin_picker"
            return view
        }
    }
}
