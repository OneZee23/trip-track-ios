import SwiftUI
import MapKit

/// The zoom hierarchy from the canon note: «далеко = страны/регионы —
/// заливка открытых, чипы стран, кластеры; средний = граница региона,
/// города-точки, фото-пины; близко = пины и линия маршрута».
enum MapZoomLevel: Int, Comparable {
    case far, region, close

    static func of(_ span: CLLocationDegrees) -> MapZoomLevel {
        if span > 3.0 { return .far }
        if span > 0.4 { return .region }
        return .close
    }

    static func < (lhs: MapZoomLevel, rhs: MapZoomLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Хозяин карты.
///
/// `UIViewControllerRepresentable`, а не `UIViewRepresentable`, ради ОДНОГО
/// свойства: `additionalSafeAreaInsets`. Логотип Apple и ссылка «Legal» — это
/// сабвью `MKMapView`, и позицию им с iOS 11 задают только инсеты
/// контроллера (`layoutMargins` перестал работать тогда же). Прятать «Legal»
/// нельзя — API для этого нет, а попытка рискует ревью; до 0.7.0 это сходило
/// с рук, потому что карта под листом была полупрозрачной и ссылка терялась
/// сама. На непрозрачном тумане перекрытие стало бы очевидным — и ревьюеру
/// тоже.
final class MapHostController: UIViewController {
    let map = MKMapView()

    /// Штора на время зума — НАД картой и под SwiftUI-хромом (хром лежит в
    /// `ZStack` выше представимого). Почему она вообще нужна и чем платим —
    /// см. `MapZoomCurtain`.
    let curtain = MapCurtain()

    /// Сколько нижней части экрана занимает постоянный лист. Логотип и
    /// «Legal» встают над ним.
    var bottomOverlayHeight: CGFloat = 0 {
        didSet { applyBottomInset() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        map.frame = view.bounds
        map.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(map)
        curtain.install(over: map, in: view)
        applyBottomInset()
    }

    /// Считается от инсетов ОКНА, а не от своих: `additionalSafeAreaInsets`
    /// меняет собственный `safeAreaInsets`, и считать от него значит гонять
    /// вью-контроллер по кругу.
    private func applyBottomInset() {
        let extra = MapBottomInset.additional(
            overlayHeight: bottomOverlayHeight,
            safeAreaBottom: UIApplication.tt_safeAreaInsets?.bottom ?? 0
        )
        guard abs(additionalSafeAreaInsets.bottom - extra) > 0.5 else { return }
        additionalSafeAreaInsets.bottom = extra
    }
}

/// Арифметика подъёма логотипа Apple и ссылки «Legal» над нижней панелью.
///
/// Чистыми функциями, потому что ошибка здесь видна только глазами на живом
/// экране, а стоит она возврата из ревью: «Legal» обязан быть виден.
enum MapBottomInset {
    /// Сколько низа экрана занимает панель — от её ВЕРХНЕГО края до
    /// физического низа окна.
    ///
    /// Панель сообщает карте именно это, а не свою высоту. Сводка чужой карты
    /// и карты машины лежит в `VStack`, который безопасную зону УВАЖАЕТ:
    /// между её низом и физическим низом окна остаются те самые 34 pt
    /// индикатора «домой», и карта, получив одну высоту сводки, поднимала
    /// «Legal» ровно на 34 pt меньше нужного — то есть прятала его под сводку.
    /// У листа Атласа высота и так считается от физического низа
    /// (`CustomTabBar.clearance`), поэтому контракт «расстояние до низа окна»
    /// — единственный, который верен для всех трёх экранов сразу.
    static func overlayHeight(panelTop: CGFloat, windowHeight: CGFloat) -> CGFloat {
        max(0, windowHeight - panelTop)
    }

    /// Добавочный инсет карты: `MKMapView` уже уважает безопасную зону окна,
    /// поэтому доплачивать надо только за то, что панель выше неё.
    static func additional(overlayHeight: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
        max(0, overlayHeight - safeAreaBottom)
    }
}

/// The night memory-map. One layer, no switches (canon: «слоёв-переключателей
/// нет») — the territory you opened and the trips you drove share it, and
/// what you can see is decided by how close you are, not by a segment.
struct MyMapRepresentable: UIViewControllerRepresentable {
    var exploration: MapExploration
    /// Открытый мир — из него же собраны оверлеи. Нужен ещё и здесь: подпись
    /// региона встаёт в середину его ОТКРЫТОЙ части.
    var revealed: RevealedLayer
    /// Непрозрачный туман поверх всего мира.
    var veil: FogVeilOverlay?
    /// Тонкая тёплая линия по оси коридоров.
    var vein: RouteVeinOverlay?
    /// Выбранная поездка — та же жилка, шире.
    var selectedRoute: RouteVeinOverlay?
    var selection: MyMapViewModel.Selection?
    /// Подписи регионов следуют языку приложения, который живёт в
    /// EnvironmentObject — координатору до него не дотянуться.
    var language: LanguageManager.Language
    /// Высота свёрнутого листа: на столько поднимаются логотип и «Legal».
    var bottomOverlayHeight: CGFloat = 0

    var onZoomLevelChange: (MapZoomLevel) -> Void
    var onSelectTrip: (UUID) -> Void
    /// Every trip whose route runs under the tapped point.
    var onSelectRoad: ([UUID]) -> Void
    var onTapMap: (CLLocationCoordinate2D) -> Void
    /// One-shot camera command; the binding is cleared once applied.
    @Binding var cameraCommand: MapCameraCommand?

    func makeUIViewController(context: Context) -> MapHostController {
        let controller = MapHostController()
        let map = controller.map
        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        map.preferredConfiguration = config
        // The memory map is ALWAYS night — Figma draws it dark regardless of
        // app theme — как и карта записи, и карта поездки с 0.7.0.
        map.overrideUserInterfaceStyle = .dark
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsScale = false
        map.showsUserLocation = true
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        map.delegate = context.coordinator

        map.register(TripPinView.self, forAnnotationViewWithReuseIdentifier: TripPinView.reuseID)
        map.register(TripClusterView.self, forAnnotationViewWithReuseIdentifier: TripClusterView.reuseID)
        map.register(CityDotView.self, forAnnotationViewWithReuseIdentifier: CityDotView.reuseID)
        map.register(RegionLabelView.self, forAnnotationViewWithReuseIdentifier: RegionLabelView.reuseID)
        map.register(RouteEndpointView.self, forAnnotationViewWithReuseIdentifier: RouteEndpointView.reuseID)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)

        // Watches the fingers so the tap handler can tell a real tap from the
        // tail of a pinch. Added after the tap so it sees the same touches.
        let fingers = FingerWatch()
        map.addGestureRecognizer(fingers)
        context.coordinator.fingers = fingers
        context.coordinator.host = controller

        return controller
    }

    func updateUIViewController(_ controller: MapHostController, context: Context) {
        let map = controller.map
        controller.bottomOverlayHeight = bottomOverlayHeight
        let coordinator = context.coordinator
        coordinator.onZoomLevelChange = onZoomLevelChange
        coordinator.onSelectTrip = onSelectTrip
        coordinator.onSelectRoad = onSelectRoad
        coordinator.onTapMap = onTapMap

        coordinator.syncData(map, exploration: exploration, revealed: revealed,
                             language: language, veil: veil, vein: vein)
        coordinator.syncSelectedRoute(map, route: selectedRoute, language: language)
        coordinator.syncSelection(map, selection: selection)
        coordinator.applyInitialCameraIfNeeded(map, exploration: exploration)

        if let command = cameraCommand {
            coordinator.apply(command, to: map)
            // Clearing during the SwiftUI update pass is not allowed.
            DispatchQueue.main.async { cameraCommand = nil }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var onZoomLevelChange: ((MapZoomLevel) -> Void)?
        var onSelectTrip: ((UUID) -> Void)?
        var onSelectRoad: (([UUID]) -> Void)?
        var onTapMap: ((CLLocationCoordinate2D) -> Void)?

        private weak var mapView: MKMapView?
        /// Хозяин карты — через него координатор достаёт штору.
        weak var host: MapHostController?
        var fingers: FingerWatch?
        private var level: MapZoomLevel = .far
        private var didSetInitialCamera = false
        private var cameraRetryScheduled = false

        private var installedTripIds: Set<UUID> = []
        private var installedRegionIds: Set<String> = []
        private var installedVeil: FogVeilOverlay?
        private var installedVein: RouteVeinOverlay?
        private var installedRoute: RouteVeinOverlay?
        private var pinsBuilt = false
        /// Which trip the current pin set was built for.
        private var pinsSelection: UUID?
        private var selectedTripId: UUID?
        private var cityAnnotations: [CityDotAnnotation] = []
        private var regionLabels: [RegionLabelAnnotation] = []
        private var exploration = MapExploration()
        private var installedLanguage: LanguageManager.Language?
        /// Routes projected into map points once, for hit-testing. Converting
        /// every vertex of every trip through `MKMapView.convert` on each tap
        /// meant hundreds of thousands of view calls before a finger got an
        /// answer; map points are the same geometry with plain arithmetic.
        private var routePoints: [(id: UUID, points: [MKMapPoint], box: MKMapRect)] = []

        // MARK: Data

        /// Порядок, снизу вверх: вуаль на `.aboveLabels`, жилка сразу за ней
        /// на том же уровне, аннотации поверх всего.
        ///
        /// Заливок регионов под вуалью больше нет. Они рисовали коричневое
        /// полотно поперёк коридоров, которые вуаль только что прочистила, и
        /// две подсказки про территорию гасили друг друга; вуаль и так
        /// говорит, что открыто, а что нет.
        func syncData(
            _ map: MKMapView,
            exploration: MapExploration,
            revealed: RevealedLayer,
            language: LanguageManager.Language,
            veil: FogVeilOverlay?,
            vein: RouteVeinOverlay?
        ) {
            mapView = map
            self.exploration = exploration

            let regionIds = Set(exploration.regions.map(\.id))
            let regionsChanged = regionIds != installedRegionIds
            if regionsChanged { installedRegionIds = regionIds }

            if installedVeil !== veil {
                map.removeOverlays(map.overlays.compactMap { $0 as? FogVeilOverlay })
                if let veil { map.addOverlay(veil, level: .aboveLabels) }
                installedVeil = veil
            }

            if installedVein !== vein {
                map.removeOverlays(map.overlays.compactMap {
                    ($0 as? RouteVeinOverlay)?.style == .network ? $0 : nil
                })
                if let vein { map.addOverlay(vein, level: .aboveLabels) }
                installedVein = vein
            }

            // Trip pins — which of them are shown depends on the zoom, so the
            // data change only invalidates the set and `syncTripPins` decides.
            let tripIds = Set(exploration.trips.map(\.id))
            let tripsChanged = tripIds != installedTripIds
            if tripsChanged {
                installedTripIds = tripIds
                map.removeAnnotations(map.annotations.filter { $0 is TripPinAnnotation })
                routePoints = exploration.trips.compactMap { trip in
                    guard trip.route.count > 1 else { return nil }
                    let points = trip.route.map { MKMapPoint($0) }
                    var box = MKMapRect(origin: points[0], size: MKMapSize(width: 0, height: 0))
                    for point in points.dropFirst() {
                        box = box.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
                    }
                    return (trip.id, points, box)
                }
            }

            // City dots and region labels are derived data, and `updateUIView`
            // runs on every published change — a selection, a camera command.
            // Rebuilding these arrays each time was pure allocation.
            if tripsChanged || regionsChanged || language != installedLanguage {
                installedLanguage = language
                // Только внутри коридоров: город, до которого ты не доезжал,
                // на карте тумана не существует. `MapExploration` уже отдаёт
                // лишь города с покрытием, но правило записано и здесь —
                // источник у него может смениться, а правило нет.
                cityAnnotations = exploration.regions.flatMap { region in
                    region.cities.filter { $0.coverage > 0 }.map {
                        CityDotAnnotation(
                            coordinate: $0.coordinate,
                            cityName: $0.localizedName(language),
                            coverage: $0.coverage
                        )
                    }
                }
                regionLabels = Self.labels(for: exploration, revealed: revealed, language: language)
                // The annotations on screen are stale copies of what just
                // changed underneath them.
                map.removeAnnotations(map.annotations.filter {
                    $0 is CityDotAnnotation || $0 is RegionLabelAnnotation
                })
            }
            applyLevel(map, animated: false)
        }

        /// Подписи — только у регионов, где есть ОТКРЫТАЯ дорога, и только в
        /// середине открытого куска.
        ///
        /// Регион без центроида пропускается молча: центр края из атласа стоял
        /// бы посреди темноты, в которой человек не был, — а подпись там
        /// обещает открытое там, где его нет.
        static func labels(
            for exploration: MapExploration,
            revealed: RevealedLayer,
            language: LanguageManager.Language
        ) -> [RegionLabelAnnotation] {
            exploration.regions.compactMap { region in
                guard region.openedKm > 0,
                      let centre = revealed.regionCentroids[region.id] else { return nil }
                return RegionLabelAnnotation(
                    regionId: region.id,
                    coordinate: centre,
                    title: region.localizedName(language).uppercased(language)
                )
            }
        }

        /// The selected trip's own line, laid over the fog, with a dot at each
        /// end — the line says which roads, never which way round.
        func syncSelectedRoute(_ map: MKMapView, route: RouteVeinOverlay?, language: LanguageManager.Language) {
            guard installedRoute !== route else { return }
            map.removeOverlays(map.overlays.compactMap {
                ($0 as? RouteVeinOverlay)?.style == .selected ? $0 : nil
            })
            map.removeAnnotations(map.annotations.filter { $0 is RouteEndpointAnnotation })
            installedRoute = route
            guard let route, let line = route.polylines(for: .fine).first,
                  line.pointCount > 1 else { return }

            map.addOverlay(route, level: .aboveLabels)
            let points = line.points()
            map.addAnnotations([
                RouteEndpointAnnotation(
                    coordinate: points[0].coordinate, isStart: true,
                    title: AppStrings.mapRouteStart(language)
                ),
                RouteEndpointAnnotation(
                    coordinate: points[line.pointCount - 1].coordinate, isStart: false,
                    title: AppStrings.mapRouteFinish(language)
                ),
            ])
        }

        /// Выбранный регион на карте больше НЕ обводится: контур — это
        /// игровая карта территорий, а туман границ не рисует. Остаётся пин
        /// выбранной поездки.
        func syncSelection(_ map: MKMapView, selection: MyMapViewModel.Selection?) {
            let newTrip: UUID?
            if case .trip(let id) = selection { newTrip = id } else { newTrip = nil }
            if newTrip != selectedTripId {
                selectedTripId = newTrip
                // `syncTripPins` rebuilds the set for the new selection, which
                // also settles the clustering: a clustered pin has no view, so
                // painting the selected look onto one was a no-op and the trip
                // you opened stayed buried in a «9» badge.
                applyLevel(map, animated: true)
            }
        }

        // MARK: Zoom level

        private func applyLevel(_ map: MKMapView, animated: Bool) {
            // Cities: only from region zoom in — at far zoom they are noise.
            let wantCities = level >= .region
            let hasCities = map.annotations.contains { $0 is CityDotAnnotation }
            if wantCities && !hasCities {
                map.addAnnotations(cityAnnotations)
            } else if !wantCities && hasCities {
                map.removeAnnotations(map.annotations.filter { $0 is CityDotAnnotation })
            }

            // Имена регионов: страна и регион. На улице ближайшая граница за
            // экраном, и подпись края там — шум поверх дорог, за которыми
            // человек и пришёл.
            let wantLabels = level <= .region
            let hasLabels = map.annotations.contains { $0 is RegionLabelAnnotation }
            if wantLabels && !hasLabels {
                map.addAnnotations(regionLabels)
            } else if !wantLabels && hasLabels {
                map.removeAnnotations(map.annotations.filter { $0 is RegionLabelAnnotation })
            }

            syncTripPins(map)
        }

        /// Every trip gets a pin, at every zoom — until you open one, and then
        /// only that one does.
        ///
        /// The zoom no longer changes the rules (a photos-only rule at street
        /// zoom read as the map losing your trips). The SELECTION does, and
        /// visibly: with sixty trips over one city, the route you just opened
        /// was one line among fifty and a dozen badges.
        private func syncTripPins(_ map: MKMapView) {
            let hasPins = map.annotations.contains { $0 is TripPinAnnotation }
            guard !pinsBuilt || pinsSelection != selectedTripId || !hasPins else { return }
            pinsBuilt = true
            pinsSelection = selectedTripId

            map.removeAnnotations(map.annotations.filter { $0 is TripPinAnnotation })
            let shown = selectedTripId.map { id in exploration.trips.filter { $0.id == id } }
                ?? exploration.trips
            map.addAnnotations(shown.map {
                TripPinAnnotation(coordinate: $0.coordinate, tripId: $0.id, photoFilename: $0.photoFilename)
            })
        }

        // MARK: Camera

        /// The initial camera must not be applied while the map still has a
        /// zero frame (setRegion on an unlaid-out MKMapView lands at a broken
        /// zoom). SwiftUI gives no post-layout callback for representables,
        /// so retry shortly.
        func applyInitialCameraIfNeeded(_ map: MKMapView, exploration: MapExploration) {
            guard !didSetInitialCamera, !exploration.isEmpty else { return }
            guard let bounds = GeoBounds(covering: exploration.trips.map(\.coordinate)) else { return }

            guard map.frame.width > 0 else {
                if !cameraRetryScheduled {
                    cameraRetryScheduled = true
                    Task { @MainActor [weak self, weak map] in
                        try? await Task.sleep(nanoseconds: 80_000_000)
                        guard let self, let map else { return }
                        self.cameraRetryScheduled = false
                        self.applyInitialCameraIfNeeded(map, exploration: exploration)
                    }
                }
                return
            }

            didSetInitialCamera = true
            map.setVisibleMapRect(
                bounds.mapRect,
                edgePadding: UIEdgeInsets(top: 140, left: 40, bottom: 200, right: 40),
                animated: false
            )
        }

        func apply(_ command: MapCameraCommand, to map: MKMapView) {
            switch command {
            case .fit(let bounds, let padding):
                didSetInitialCamera = true
                map.setVisibleMapRect(bounds.mapRect, edgePadding: padding.insets, animated: true)
            }
        }

        // MARK: Delegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            // Вуаль НИКОГДА не приглушается: приглушённый туман — это снова
            // полупрозрачная вуаль, ради снятия которой всё и затевалось.
            if let veil = overlay as? FogVeilOverlay {
                return FogVeilRenderer(veil: veil)
            }
            if let vein = overlay as? RouteVeinOverlay {
                return RouteVeinRenderer(vein: vein)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case is MKUserLocation:
                return nil
            case let cluster as MKClusterAnnotation:
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: TripClusterView.reuseID, for: cluster)
                return view
            case let city as CityDotAnnotation:
                return mapView.dequeueReusableAnnotationView(
                    withIdentifier: CityDotView.reuseID, for: city)
            case let label as RegionLabelAnnotation:
                return mapView.dequeueReusableAnnotationView(
                    withIdentifier: RegionLabelView.reuseID, for: label)
            case let endpoint as RouteEndpointAnnotation:
                return mapView.dequeueReusableAnnotationView(
                    withIdentifier: RouteEndpointView.reuseID, for: endpoint)
            case let pin as TripPinAnnotation:
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: TripPinView.reuseID, for: pin) as? TripPinView
                view?.setSelectedAppearance(pin.tripId == selectedTripId)
                return view
            default:
                return nil
            }
        }

        /// MapKit's own selection is not used to drive anything: it fired for
        /// clusters but never for trip pins on this SDK — the pin highlighted
        /// and nothing opened. One tap handler below decides everything
        /// instead, so behaviour does not depend on which selection callback
        /// the current iOS happens to send. This just clears MapKit's state so
        /// no annotation stays stuck in its selected look.
        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            mapView.deselectAnnotation(annotation, animated: false)
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation else { return }
            mapView.deselectAnnotation(annotation, animated: false)
        }

        // MARK: Штора на время зума

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            host?.curtain.willChange(mapView)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            host?.curtain.changing(mapView)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            host?.curtain.didChange(mapView)
            let newLevel = MapZoomLevel.of(mapView.region.span.latitudeDelta)
            guard newLevel != level else { return }
            level = newLevel
            applyLevel(mapView, animated: true)
            onZoomLevelChange?(newLevel)
        }

        // MARK: Tap

        /// The single entry point for every tap on the map: pin, cluster, or
        /// the territory behind them. Doing the hit test here rather than
        /// splitting it between this recogniser and MapKit's selection is what
        /// makes «tap a pin → trip card» work at all, and it also stops a
        /// cluster tap from selecting the region underneath it.
        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let map = mapView else { return }
            // Pinching out to see more of the map used to open whichever
            // region the last finger happened to be over: two fingers rarely
            // land or lift together, and the straggler reads as a clean tap.
            guard !FingerWatch.shouldIgnoreTap(
                activeTouches: fingers?.activeTouches ?? 0,
                secondsSinceMultiTouch: fingers?.secondsSinceMultiTouch
            ) else { return }
            let point = recognizer.location(in: map)

            var nearest: (annotation: MKAnnotation, distance: CGFloat)?
            for annotation in map.annotations {
                // Route endpoints are labels on the trip already open. Letting
                // them win the hit test would swallow taps meant for the road.
                guard !(annotation is RouteEndpointAnnotation) else { continue }
                // Подпись региона стоит ровно в СЕРЕДИНЕ открытого, то есть
                // поверх дорог, и «попал в подпись» там значит «попал в свою
                // дорогу». Выбывает из хит-теста по той же причине, что и
                // концы маршрута: тап обязан дойти до дороги под ней.
                guard !(annotation is RegionLabelAnnotation) else { continue }
                guard let view = map.view(for: annotation), !view.isHidden else { continue }
                let target = view.frame.insetBy(dx: -6, dy: -6)
                guard target.contains(point) else { continue }
                let distance = hypot(view.center.x - point.x, view.center.y - point.y)
                if nearest == nil || distance < nearest!.distance {
                    nearest = (annotation, distance)
                }
            }

            if let hit = nearest?.annotation {
                if let cluster = hit as? MKClusterAnnotation {
                    zoom(into: cluster, on: map)
                } else if let pin = hit as? TripPinAnnotation {
                    Haptics.tap()
                    onSelectTrip?(pin.tripId)
                }
                // Точка города — подпись, а не контрол: тап по ней не делает
                // ничего (так было и до 0.7.0).
                return
            }

            // Nothing pinned here — but the road under your finger belongs to
            // a trip, and up close that road is the only thing on screen. This
            // is what makes it fine to drop most pins at street zoom.
            if level != .far {
                let onThisRoad = trips(near: point, on: map)
                if !onThisRoad.isEmpty {
                    Haptics.tap()
                    onSelectRoad?(onThisRoad)
                    return
                }
            }
            onTapMap?(map.convert(point, toCoordinateFrom: map))
        }

        /// Every trip whose route passes within finger reach of a screen
        /// point, closest first.
        ///
        /// Returning only the nearest one is what made the map feel like it
        /// held four trips: the roads you drive most belong to a dozen, and
        /// tapping one always answered with the same trip.
        ///
        /// Preview polylines are short (a few hundred vertices) and this runs
        /// once per tap.
        private func trips(near point: CGPoint, on map: MKMapView) -> [UUID] {
            guard map.bounds.width > 0 else { return [] }
            // Everything below is in MAP points, so one conversion is all the
            // map view is asked for.
            let mapPointsPerScreenPoint = map.visibleMapRect.width / Double(map.bounds.width)
            let reach = 26 * mapPointsPerScreenPoint
            let target = MKMapPoint(map.convert(point, toCoordinateFrom: map))
            let touch = MKMapRect(x: target.x - reach, y: target.y - reach,
                                  width: reach * 2, height: reach * 2)

            var hits: [(id: UUID, distance: Double)] = []
            for route in routePoints {
                // Whole-route reject first: at street zoom this discards every
                // trip on the other side of the country in one comparison.
                guard route.box.insetBy(dx: -reach, dy: -reach).intersects(touch) else { continue }
                var best = Double.greatestFiniteMagnitude
                var previous = route.points[0]
                for index in 1..<route.points.count {
                    let current = route.points[index]
                    defer { previous = current }
                    guard min(previous.x, current.x) - reach <= target.x,
                          target.x <= max(previous.x, current.x) + reach,
                          min(previous.y, current.y) - reach <= target.y,
                          target.y <= max(previous.y, current.y) + reach
                    else { continue }
                    best = min(best, Self.distance(from: target, toSegment: previous, current))
                }
                if best <= reach { hits.append((route.id, best)) }
            }
            return hits.sorted { $0.distance < $1.distance }.map(\.id)
        }

        private static func distance(
            from p: MKMapPoint, toSegment a: MKMapPoint, _ b: MKMapPoint
        ) -> Double {
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
            let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
            return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
        }

        private func zoom(into cluster: MKClusterAnnotation, on map: MKMapView) {
            Haptics.selection()
            var box = MKMapRect.null
            for member in cluster.memberAnnotations {
                box = box.union(MKMapRect(
                    origin: MKMapPoint(member.coordinate),
                    size: MKMapSize(width: 1, height: 1)
                ))
            }
            guard !box.isNull else { return }
            // Trips that all start on the same driveway cluster into a
            // zero-size box, and zooming to that lands on the map's tightest
            // level with nothing readable on screen.
            let floor = 400 * MKMapPointsPerMeterAtLatitude(
                MKMapPoint(x: box.midX, y: box.midY).coordinate.latitude)
            if box.width < floor || box.height < floor {
                box = MKMapRect(
                    x: box.midX - max(box.width, floor) / 2,
                    y: box.midY - max(box.height, floor) / 2,
                    width: max(box.width, floor),
                    height: max(box.height, floor)
                )
            }
            map.setVisibleMapRect(
                box,
                edgePadding: UIEdgeInsets(top: 140, left: 60, bottom: 220, right: 60),
                animated: true
            )
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

    }
}

// MARK: - Нижняя панель

extension View {
    /// Сообщает карте, сколько низа экрана занимает её нижняя панель, — карта
    /// ровно на столько поднимает логотип Apple и ссылку «Legal»
    /// (`additionalSafeAreaInsets`).
    ///
    /// Измеряется, а не вписано числом: у сводки чужой карты высота зависит от
    /// содержимого (загрузка, отказ, пустота, числа), и неверная константа
    /// оставила бы «Legal» под панелью — то самое, из-за чего ревью
    /// возвращает сборки.
    ///
    /// Меряется РАССТОЯНИЕ ДО НИЗА ОКНА, а не собственная высота панели: см.
    /// `MapBottomInset.overlayHeight`. Следить достаточно за верхним краем —
    /// он двигается и когда панель растёт, и когда её кто-то поднял.
    func measuredBottomOverlay(_ height: Binding<CGFloat>) -> some View {
        background(
            GeometryReader { geo in
                let top = geo.frame(in: .global).minY
                Color.clear
                    .onAppear { height.wrappedValue = MapBottomInset.overlayHeight(
                        panelTop: top,
                        windowHeight: UIApplication.tt_windowHeight ?? (top + geo.size.height)
                    ) }
                    .onChange(of: top) { _, new in
                        height.wrappedValue = MapBottomInset.overlayHeight(
                            panelTop: new,
                            windowHeight: UIApplication.tt_windowHeight ?? (new + geo.size.height)
                        )
                    }
            }
        )
    }
}
