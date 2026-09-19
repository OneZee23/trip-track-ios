import SwiftUI
import MapKit

/// Карта листа «Вписать поездку»: булавки точек, линия маршрута, тап по карте.
///
/// Своя, а не `RouteMapView`: у той один маршрут из трека поездки, реплей,
/// туман и общий с полноэкранным слоем хост — здесь ничего из этого нет, а
/// нужно ровно обратное, тап по пустому месту. Тот же довод, по которому
/// `PlacesMapView` не стала её настройкой.
struct ManualTripMapView: UIViewRepresentable {
    /// В порядке следования: откуда → промежуточные → куда.
    let points: [ManualTripPoint]
    /// Линия, посчитанная `MKDirections`. Пустая — рисуем только булавки.
    let route: [CLLocationCoordinate2D]
    /// Тап по карте. `nil` — карта только показывает (точку сейчас никто не
    /// ждёт), и жест не ставится вовсе.
    var onTap: ((CLLocationCoordinate2D) -> Void)?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsCompass = false
        map.showsScale = false
        // Наклон выключен на всех наших картах с 0.7.0 — здесь просто нечему
        // его использовать, а перспектива ломает попадание пальцем по точке.
        map.isPitchEnabled = false
        map.pointOfInterestFilter = .excludingAll
        let tap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        map.addGestureRecognizer(tap)
        context.coordinator.tap = tap
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.tap?.isEnabled = onTap != nil

        let wanted = points.map(\.coordinate)
        if !context.coordinator.annotationsMatch(wanted) {
            map.removeAnnotations(map.annotations)
            for (index, point) in points.enumerated() {
                let pin = MKPointAnnotation()
                pin.coordinate = point.coordinate
                pin.title = point.name
                pin.subtitle = "\(index)"
                map.addAnnotation(pin)
            }
            context.coordinator.annotated = wanted
        }

        // Сравнение ПО СОДЕРЖИМОМУ, а не по числу точек: пересчёт маршрута
        // может вернуть линию той же длины другой формы (сменили
        // промежуточную точку рядом со старой), и счётчик такую подмену не
        // заметил бы — та же ловушка, что у `PlacesMapView.routesMatch`.
        if !context.coordinator.routeMatches(route) {
            map.removeOverlays(map.overlays)
            if route.count > 1 {
                map.addOverlay(MKPolyline(coordinates: route, count: route.count))
            }
            context.coordinator.drawn = route
            fit(map, to: route.isEmpty ? wanted : route)
        } else if context.coordinator.drawn.isEmpty && !wanted.isEmpty
                    && !context.coordinator.annotationsMatch(context.coordinator.fitted) {
            fit(map, to: wanted)
        }
    }

    private func fit(_ map: MKMapView, to coords: [CLLocationCoordinate2D]) {
        guard !coords.isEmpty else { return }
        let rect = coords.reduce(MKMapRect.null) { acc, coord in
            let point = MKMapPoint(coord)
            return acc.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        guard !rect.isNull else { return }
        map.setVisibleMapRect(
            rect,
            edgePadding: UIEdgeInsets(top: 44, left: 36, bottom: 36, right: 36),
            animated: true
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onTap: ((CLLocationCoordinate2D) -> Void)?
        var tap: UITapGestureRecognizer?
        var annotated: [CLLocationCoordinate2D] = []
        var drawn: [CLLocationCoordinate2D] = []
        var fitted: [CLLocationCoordinate2D] = []

        func annotationsMatch(_ coords: [CLLocationCoordinate2D]) -> Bool {
            same(annotated, coords)
        }

        func routeMatches(_ coords: [CLLocationCoordinate2D]) -> Bool {
            same(drawn, coords)
        }

        private func same(_ a: [CLLocationCoordinate2D], _ b: [CLLocationCoordinate2D]) -> Bool {
            guard a.count == b.count else { return false }
            for (x, y) in zip(a, b) where x.latitude != y.latitude || x.longitude != y.longitude {
                return false
            }
            return true
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView, let onTap else { return }
            let coord = map.convert(gesture.location(in: map), toCoordinateFrom: map)
            onTap(coord)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = UIColor(AppTheme.accent)
            renderer.lineWidth = 5
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is MKPointAnnotation else { return nil }
            let id = "manualTripPin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.markerTintColor = UIColor(AppTheme.accent)
            view.glyphImage = UIImage(systemName: "mappin")
            view.canShowCallout = false
            return view
        }
    }
}
