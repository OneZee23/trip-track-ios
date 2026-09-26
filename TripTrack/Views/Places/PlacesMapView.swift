import SwiftUI
import MapKit

struct PlacePin: Identifiable, Equatable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    /// Подсказка (`PlaceSuggestions`), а не заведённое место: рисуется
    /// пустой, серой и пунктиром — «сюда МОЖНО поставить булавку», а не
    /// «здесь она стоит». Входит в сравнение: одна и та же ячейка меняет вид,
    /// когда подсказка становится местом, а координата у неё та же.
    var isSuggested = false
    /// Подпись ВЫБРАННОЙ булавки. У остальных не рисуется: десяток имён на
    /// карте города перекрывают и друг друга, и сам маршрут.
    var name: String? = nil
    static func == (a: PlacePin, b: PlacePin) -> Bool {
        a.id == b.id && a.isSuggested == b.isSuggested && a.name == b.name
            && a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude
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
        private var shownRoutes: [[CLLocationCoordinate2D]] = []
        private var fitted = false
        /// Запомненный выбор: `mapView(_:viewFor:)` красит свежесозданную
        /// булавку сразу, не дожидаясь следующего `sync()` — на момент
        /// дозапроса вида `map.view(for:)` эту аннотацию ещё не видит.
        private var selectedId: UUID?

        func sync(pins: [PlacePin], routes: [[CLLocationCoordinate2D]], selectedId: UUID?, on map: MKMapView) {
            self.selectedId = selectedId
            if pins != shownPins {
                map.removeAnnotations(map.annotations)
                map.addAnnotations(pins.map { PlaceAnnotation(pin: $0) })
                shownPins = pins
                fitted = false
            }
            if !Self.routesMatch(routes, shownRoutes) {
                map.removeOverlays(map.overlays)
                map.addOverlays(routes.filter { $0.count > 1 }.map { MKPolyline(coordinates: $0, count: $0.count) })
                shownRoutes = routes
                fitted = false
            }
            for case let view as PlacePinView in map.annotations.compactMap({ map.view(for: $0) }) {
                let pin = (view.annotation as? PlaceAnnotation)?.pin
                view.setSelectedAppearance(pin?.id == selectedId, name: pin?.name)
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

        /// Сравнение ПО СОДЕРЖИМОМУ, а не по числу маршрутов: на экране места
        /// (Task 4) один набор ниток сменяется другим той же длины (сверка
        /// задним числом поменяла проезд, не поменяв их количество) — счётчик
        /// такую подмену не заметил бы, и карта осталась бы со старыми
        /// нитками. `CLLocationCoordinate2D` не `Equatable`, поэтому руками.
        private static func routesMatch(_ a: [[CLLocationCoordinate2D]], _ b: [[CLLocationCoordinate2D]]) -> Bool {
            guard a.count == b.count else { return false }
            for (ra, rb) in zip(a, b) {
                guard ra.count == rb.count,
                      ra.elementsEqual(rb, by: { $0.latitude == $1.latitude && $0.longitude == $1.longitude })
                else { return false }
            }
            return true
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let place = annotation as? PlaceAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: PlacePinView.reuseID, for: annotation)
            // Свежедобавленная булавка ещё не видна `map.view(for:)` в цикле
            // ниже по `sync()`, а переиспользованный вид мог прийти с чужим
            // масштабом — красим по актуальному выбору здесь же.
            (view as? PlacePinView)?.setSuggested(place.pin.isSuggested)
            (view as? PlacePinView)?.setSelectedAppearance(place.pin.id == selectedId, name: place.pin.name)
            return view
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

/// Булавка места (макет «Места» 0.8.1, S8).
///
/// Три состояния и все три обязаны читаться НА ЛЮБОМ фоне — на открытой
/// карте, на тумане «Атласа» и в тёмной теме, — поэтому у каждой белая
/// обводка и тень, а не просто свой цвет:
/// - место — залитый терракотой диск с белой точкой в середине;
/// - подсказка — белый диск с ПУНКТИРНЫМ серым кольцом: заведённое важнее
///   предложенного, и терракота предложенному не достаётся;
/// - выбранное — крупнее и с подписью над ним.
final class PlacePinView: MKAnnotationView {
    static let reuseID = "PlacePin"

    /// Диаметры из макета. Подсказка меньше места нарочно: разница видна и
    /// там, где обе булавки рядом, а цвет уже занят другим различием.
    private static let placeSize: CGFloat = 28
    private static let suggestedSize: CGFloat = 24

    private let disc = UIView()
    private let dot = UIView()
    private let ring = CAShapeLayer()
    private let label = UILabel()
    /// Вторая строка подписи — «6 сент.» у места на «Атласе».
    private let detailLabel = UILabel()
    private let labelBox = UIView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: Self.placeSize, height: Self.placeSize)
        centerOffset = .zero
        collisionMode = .circle
        displayPriority = .required
        // Подпись рисуется ВЫШЕ своих границ — обрезать её нельзя. Нажатие
        // от этого не страдает: ловится диск, а подпись не кнопка.
        clipsToBounds = false

        disc.layer.borderColor = UIColor.white.cgColor
        disc.layer.borderWidth = 2.6
        disc.layer.shadowColor = UIColor.black.cgColor
        disc.layer.shadowOpacity = 0.18
        disc.layer.shadowRadius = 3
        disc.layer.shadowOffset = CGSize(width: 0, height: 1.5)
        addSubview(disc)

        ring.fillColor = nil
        ring.lineWidth = 2
        ring.lineDashPattern = [3.2, 2.6]
        ring.isHidden = true
        disc.layer.addSublayer(ring)

        dot.isUserInteractionEnabled = false
        disc.addSubview(dot)

        labelBox.backgroundColor = UIColor(AtlasTheme.control)
        labelBox.layer.cornerRadius = 10
        labelBox.layer.cornerCurve = .continuous
        labelBox.layer.shadowColor = UIColor.black.cgColor
        labelBox.layer.shadowOpacity = 0.18
        labelBox.layer.shadowRadius = 4
        labelBox.layer.shadowOffset = CGSize(width: 0, height: 2)
        labelBox.isHidden = true
        label.font = UIFont(name: "Inter-Medium", size: 12) ?? .systemFont(ofSize: 12, weight: .medium)
        label.textColor = UIColor(AtlasTheme.ink)
        label.textAlignment = .center
        detailLabel.font = UIFont(name: "Inter-Regular", size: 12) ?? .systemFont(ofSize: 12)
        detailLabel.textColor = UIColor(AtlasTheme.secondary)
        detailLabel.textAlignment = .center
        detailLabel.isHidden = true
        labelBox.addSubview(label)
        labelBox.addSubview(detailLabel)
        addSubview(labelBox)

        isAccessibilityElement = true
        accessibilityIdentifier = "place_pin"
        applyStyle(.place)
    }
    required init?(coder: NSCoder) { nil }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Иначе переиспользованный вид мог на кадр мелькнуть с прежним
        // масштабом и чужой подписью до того, как `viewFor` перекрасит его.
        setSelectedAppearance(false, name: nil)
        setSuggested(false)
    }

    /// Вид булавки. Три, и ни одного «просто другого цвета»: подсказка
    /// пунктиром, место вне периода приглушено, заведённое горит акцентом.
    enum Kind { case place, suggestion, outOfPeriod }

    func setSuggested(_ suggested: Bool) { setKind(suggested ? .suggestion : .place) }

    func setKind(_ kind: Kind) {
        applyStyle(kind)
        // Место всегда побеждает подсказку в споре за пиксель: заведённое
        // важнее предложенного, а место вне периода — важнее подсказки, но
        // уступает своим.
        switch kind {
        case .place: displayPriority = .required
        case .outOfPeriod: displayPriority = .defaultHigh
        case .suggestion: displayPriority = .defaultLow
        }
    }

    func setSelectedAppearance(_ selected: Bool, name: String?) {
        setSelectedAppearance(selected, name: name, detail: nil, alwaysLabelled: false)
    }

    /// `alwaysLabelled` — подпись стоит и у невыбранной булавки: так рисует
    /// «Атлас» (S8), где имя места это половина смысла карты. На вкладке
    /// «Места» подпись только у выбранной: десяток имён на карте города
    /// перекрывают и друг друга, и сам маршрут.
    func setSelectedAppearance(_ selected: Bool, name: String?, detail: String?,
                               alwaysLabelled: Bool) {
        transform = selected ? CGAffineTransform(scaleX: 1.2, y: 1.2) : .identity
        guard selected || alwaysLabelled, let name, !name.isEmpty else {
            labelBox.isHidden = true
            return
        }
        labelBox.isHidden = false
        label.text = name
        detailLabel.text = detail
        detailLabel.isHidden = detail == nil || detail?.isEmpty == true

        let cap = CGSize(width: 160, height: CGFloat.greatestFiniteMagnitude)
        let nameSize = label.sizeThatFits(cap)
        let detailSize = detailLabel.isHidden ? .zero : detailLabel.sizeThatFits(cap)
        let boxWidth = min(160, max(nameSize.width, detailSize.width)) + 16
        let boxHeight = nameSize.height + (detailLabel.isHidden ? 0 : detailSize.height) + 8
        labelBox.frame = CGRect(x: (bounds.width - boxWidth) / 2, y: -(boxHeight + 6),
                                width: boxWidth, height: boxHeight)
        label.frame = CGRect(x: 8, y: 4, width: boxWidth - 16, height: nameSize.height)
        detailLabel.frame = CGRect(x: 8, y: 4 + nameSize.height, width: boxWidth - 16, height: detailSize.height)
    }

    private func applyStyle(_ kind: Kind) {
        let suggested = kind == .suggestion
        let side = suggested ? Self.suggestedSize : Self.placeSize
        bounds = CGRect(x: 0, y: 0, width: side, height: side)
        disc.frame = bounds
        disc.layer.cornerRadius = side / 2
        switch kind {
        case .place: disc.backgroundColor = UIColor(AppTheme.accent)
        case .outOfPeriod: disc.backgroundColor = UIColor(AtlasTheme.mutedPin)
        case .suggestion: disc.backgroundColor = UIColor(AtlasTheme.control)
        }
        disc.layer.borderWidth = suggested ? 0 : 2.6

        ring.isHidden = !suggested
        if suggested {
            let inset: CGFloat = 3
            ring.strokeColor = UIColor(AtlasTheme.secondary).cgColor
            ring.path = UIBezierPath(ovalIn: bounds.insetBy(dx: inset, dy: inset)).cgPath
            ring.frame = bounds
        }

        let dotSide: CGFloat = suggested ? 5.2 : 9
        dot.frame = CGRect(x: (side - dotSide) / 2, y: (side - dotSide) / 2, width: dotSide, height: dotSide)
        dot.layer.cornerRadius = dotSide / 2
        dot.backgroundColor = suggested ? UIColor(AtlasTheme.secondary) : .white
    }
}
