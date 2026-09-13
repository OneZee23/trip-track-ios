import SwiftUI
import MapKit

struct PlacePin: Identifiable, Equatable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    static func == (a: PlacePin, b: PlacePin) -> Bool {
        a.id == b.id && a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude
    }
}

/// Карта мест: булавки и, на экране места, нитки проездов. Своя, а не
/// `RouteMapView`: та рисует ОДИН маршрут и подбирает область по нему — без
/// трека область не подберёт, а список мест соединила бы линией.
/// Стиль карты — тот же, что у `RouteMapView.makeUIView`: стандартная
/// конфигурация, без POI, без компаса и масштаба.
struct PlacesMapView: UIViewRepresentable {
    let pins: [PlacePin]
    var routes: [[CLLocationCoordinate2D]] = []
    var selectedId: UUID? = nil
    var isInteractive: Bool = true
    var onPinTap: ((UUID) -> Void)? = nil

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = false
        map.isScrollEnabled = isInteractive
        map.isZoomEnabled = isInteractive
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsCompass = false
        map.showsScale = false
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        map.pointOfInterestFilter = .excludingAll
        map.register(PlacePinView.self, forAnnotationViewWithReuseIdentifier: PlacePinView.reuseID)
        map.accessibilityIdentifier = "places_map"
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.onPinTap = onPinTap
        context.coordinator.sync(pins: pins, routes: routes, selectedId: selectedId, on: map)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onPinTap: ((UUID) -> Void)?
        private var shownPins: [PlacePin] = []
        private var shownRouteCount = -1
        private var fitted = false

        func sync(pins: [PlacePin], routes: [[CLLocationCoordinate2D]], selectedId: UUID?, on map: MKMapView) {
            if pins != shownPins {
                map.removeAnnotations(map.annotations)
                map.addAnnotations(pins.map { PlaceAnnotation(pin: $0) })
                shownPins = pins
                fitted = false
            }
            if routes.count != shownRouteCount {
                map.removeOverlays(map.overlays)
                map.addOverlays(routes.filter { $0.count > 1 }.map { MKPolyline(coordinates: $0, count: $0.count) })
                shownRouteCount = routes.count
                fitted = false
            }
            for case let view as PlacePinView in map.annotations.compactMap({ map.view(for: $0) }) {
                view.setSelectedAppearance((view.annotation as? PlaceAnnotation)?.pin.id == selectedId)
            }
            guard !fitted, !pins.isEmpty else { return }
            fitted = true
            // Область — по всем булавкам и ниткам; одна булавка — двор в 1.5 км.
            var rect = MKMapRect.null
            for pin in pins { rect = rect.union(MKMapRect(origin: MKMapPoint(pin.coordinate), size: MKMapSize(width: 1, height: 1))) }
            for overlay in map.overlays { rect = rect.union(overlay.boundingMapRect) }
            if pins.count == 1 && map.overlays.isEmpty {
                map.setRegion(MKCoordinateRegion(center: pins[0].coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500), animated: false)
            } else {
                map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40), animated: false)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is PlaceAnnotation else { return nil }
            return mapView.dequeueReusableAnnotationView(withIdentifier: PlacePinView.reuseID, for: annotation)
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let pin = (view.annotation as? PlaceAnnotation)?.pin else { return }
            mapView.deselectAnnotation(view.annotation, animated: false)
            onPinTap?(pin.id)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: line)
            // Нитки проездов — приглушённый акцент: контекст, не содержание.
            r.strokeColor = UIColor(AppTheme.accent).withAlphaComponent(0.35)
            r.lineWidth = 3
            r.lineCap = .round
            return r
        }
    }
}

final class PlaceAnnotation: NSObject, MKAnnotation {
    let pin: PlacePin
    var coordinate: CLLocationCoordinate2D { pin.coordinate }
    init(pin: PlacePin) { self.pin = pin }
}

/// Булавка места — оранжевый диск в белом кольце, как компактный маркер
/// отметки на карте поездки (S1); выбранная — крупнее.
final class PlacePinView: MKAnnotationView {
    static let reuseID = "PlacePin"
    private let disc = UIView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 18, height: 18)
        centerOffset = .zero
        collisionMode = .circle
        displayPriority = .required
        disc.frame = bounds
        disc.layer.cornerRadius = 9
        disc.backgroundColor = UIColor(AppTheme.accent)
        disc.layer.borderColor = UIColor.white.cgColor
        disc.layer.borderWidth = 3
        disc.layer.shadowColor = UIColor.black.cgColor
        disc.layer.shadowOpacity = 0.25
        disc.layer.shadowRadius = 3
        disc.layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(disc)
        isAccessibilityElement = true
        accessibilityIdentifier = "place_pin"
    }
    required init?(coder: NSCoder) { nil }

    func setSelectedAppearance(_ selected: Bool) {
        transform = selected ? CGAffineTransform(scaleX: 1.35, y: 1.35) : .identity
    }
}
