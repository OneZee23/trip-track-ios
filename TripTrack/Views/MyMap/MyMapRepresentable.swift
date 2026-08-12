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

/// The night memory-map. One layer, no switches (canon: «слоёв-переключателей
/// нет») — the territory you opened and the trips you drove share it, and
/// what you can see is decided by how close you are, not by a segment.
struct MyMapRepresentable: UIViewRepresentable {
    var exploration: MapExploration
    /// The driven network, one overlay for every zoom.
    var fog: RoadFogOverlay?
    /// The dark over everywhere the network has not reached.
    var veil: FogOfWarOverlay?
    /// Only the selected trip is drawn as its own gradient line.
    var selectedRoute: SpeedGradientPolyline?
    var selection: MyMapViewModel.Selection?
    var highlightedRegionId: String?
    /// Chip labels follow the app language, which lives in an
    /// EnvironmentObject the coordinator cannot reach.
    var language: LanguageManager.Language

    var onZoomLevelChange: (MapZoomLevel) -> Void
    var onSelectTrip: (UUID) -> Void
    /// Every trip whose route runs under the tapped point.
    var onSelectRoad: ([UUID]) -> Void
    var onTapMap: (CLLocationCoordinate2D) -> Void
    /// One-shot camera command; the binding is cleared once applied.
    @Binding var cameraCommand: MapCameraCommand?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        map.preferredConfiguration = config
        // The memory map is ALWAYS night — Figma draws it dark regardless of
        // app theme (unlike the tracking map's sun-driven isDarkMap).
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
        map.register(CountryChipView.self, forAnnotationViewWithReuseIdentifier: CountryChipView.reuseID)
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

        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onZoomLevelChange = onZoomLevelChange
        coordinator.onSelectTrip = onSelectTrip
        coordinator.onSelectRoad = onSelectRoad
        coordinator.onTapMap = onTapMap

        coordinator.syncData(map, exploration: exploration, language: language,
                             fog: fog, veil: veil)
        coordinator.syncSelectedRoute(map, route: selectedRoute, language: language)
        coordinator.syncHighlight(map, regionId: highlightedRegionId, selection: selection)
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
        var fingers: FingerWatch?
        private var level: MapZoomLevel = .far
        private var didSetInitialCamera = false
        private var cameraRetryScheduled = false

        private var installedTripIds: Set<UUID> = []
        private var installedRegionIds: Set<String> = []
        private var installedFog: RoadFogOverlay?
        private var installedVeil: FogOfWarOverlay?
        private var installedRoute: SpeedGradientPolyline?
        private var pinsBuilt = false
        /// Which trip the current pin set was built for.
        private var pinsSelection: UUID?
        private var highlightRegionId: String?
        private var selectedTripId: UUID?
        private var cityAnnotations: [CityDotAnnotation] = []
        private var chipAnnotations: [CountryChipAnnotation] = []
        private var exploration = MapExploration()
        private var installedLanguage: LanguageManager.Language?
        /// Routes projected into map points once, for hit-testing. Converting
        /// every vertex of every trip through `MKMapView.convert` on each tap
        /// meant hundreds of thousands of view calls before a finger got an
        /// answer; map points are the same geometry with plain arithmetic.
        private var routePoints: [(id: UUID, points: [MKMapPoint], box: MKMapRect)] = []

        // MARK: Data

        /// Z-order, bottom to top: opened-region fills on `.aboveRoads`, then
        /// the veil, the heat network, the selected route and the region
        /// highlight on `.aboveLabels`, in that insertion order (the callers
        /// run in that sequence every update).
        ///
        /// The fills go UNDER the veil on purpose. Over it they painted a
        /// brown sheet across the corridors the veil had just cleared, and the
        /// two territory cues cancelled each other out. Under it, the veil's
        /// dark is what you have not opened and the fill only shows through
        /// where you have — which is the whole idea.
        func syncData(
            _ map: MKMapView,
            exploration: MapExploration,
            language: LanguageManager.Language,
            fog: RoadFogOverlay?,
            veil: FogOfWarOverlay?
        ) {
            mapView = map
            self.exploration = exploration

            // Region fills — one polygon per opened region, added once.
            let regionIds = Set(exploration.regions.map(\.id))
            let regionsChanged = regionIds != installedRegionIds
            if regionsChanged {
                // Only the fills — the highlight tracing the selected region
                // is owned by `syncHighlight` and must survive a data refresh.
                let stale = map.overlays.compactMap { $0 as? RegionPolygon }
                    .filter { $0.style == .opened }
                map.removeOverlays(stale)
                for id in regionIds {
                    guard let region = RegionAtlas.shared.region(id: id) else { continue }
                    for polygon in Self.polygons(for: region, style: .opened) {
                        map.addOverlay(polygon, level: .aboveRoads)
                    }
                }
                installedRegionIds = regionIds
            }

            if installedVeil !== veil {
                map.removeOverlays(map.overlays.compactMap { $0 as? FogOfWarOverlay })
                if let veil { map.addOverlay(veil, level: .aboveLabels) }
                installedVeil = veil
            }

            if installedFog !== fog {
                map.removeOverlays(map.overlays.compactMap { $0 as? RoadFogOverlay })
                if let fog { map.addOverlay(fog, level: .aboveLabels) }
                installedFog = fog
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

            // City dots and country chips are derived data, and `updateUIView`
            // runs on every published change — a selection, a camera command.
            // Rebuilding these arrays each time was pure allocation.
            if tripsChanged || regionsChanged || language != installedLanguage {
                installedLanguage = language
                cityAnnotations = exploration.regions.flatMap { region in
                    region.cities.map {
                        CityDotAnnotation(
                            coordinate: $0.coordinate,
                            cityName: $0.localizedName(language),
                            coverage: $0.coverage
                        )
                    }
                }
                chipAnnotations = Self.countryChips(for: exploration, language: language)
                // The annotations on screen are stale copies of what just
                // changed underneath them.
                map.removeAnnotations(map.annotations.filter {
                    $0 is CityDotAnnotation || $0 is CountryChipAnnotation
                })
            }
            applyLevel(map, animated: false)
        }

        /// The selected trip's own line, laid over the fog, with a dot at each
        /// end — the line says which roads, never which way round.
        func syncSelectedRoute(_ map: MKMapView, route: SpeedGradientPolyline?, language: LanguageManager.Language) {
            guard installedRoute !== route else { return }
            map.removeOverlays(map.overlays.compactMap { $0 as? SpeedGradientPolyline })
            map.removeAnnotations(map.annotations.filter { $0 is RouteEndpointAnnotation })
            installedRoute = route
            guard let route, route.pointCount > 1 else { return }

            map.addOverlay(route, level: .aboveLabels)
            let points = route.points()
            map.addAnnotations([
                RouteEndpointAnnotation(
                    coordinate: points[0].coordinate, isStart: true,
                    title: AppStrings.mapRouteStart(language)
                ),
                RouteEndpointAnnotation(
                    coordinate: points[route.pointCount - 1].coordinate, isStart: false,
                    title: AppStrings.mapRouteFinish(language)
                ),
            ])
        }

        func syncHighlight(_ map: MKMapView, regionId: String?, selection: MyMapViewModel.Selection?) {
            if regionId != highlightRegionId {
                highlightRegionId = regionId
                map.removeOverlays(map.overlays.compactMap { $0 as? RegionPolygon }
                    .filter { $0.style != .opened })
                if let regionId, let region = RegionAtlas.shared.region(id: regionId) {
                    // An opened region gets the bright traced border; one you
                    // have never driven in gets the dashed outline instead.
                    let isOpen = installedRegionIds.contains(regionId)
                    let polygons = Self.polygons(for: region, style: isOpen ? .selected : .locked)
                    map.addOverlays(polygons, level: .aboveLabels)
                }
            }

            let newTrip: UUID?
            if case .trip(let id) = selection { newTrip = id } else { newTrip = nil }
            if newTrip != selectedTripId {
                selectedTripId = newTrip
                // `syncTripPins` rebuilds the set for the new selection, which
                // also settles the clustering: a clustered pin has no view, so
                // painting the selected look onto one was a no-op and the trip
                // you opened stayed buried in a «9» badge.
                applyLevel(map, animated: true)
                refreshFocus(map)
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

            // Country chips: far zoom only.
            let wantChips = level == .far
            let hasChips = map.annotations.contains { $0 is CountryChipAnnotation }
            if wantChips && !hasChips {
                map.addAnnotations(chipAnnotations)
            } else if !wantChips && hasChips {
                map.removeAnnotations(map.annotations.filter { $0 is CountryChipAnnotation })
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

        /// Fades the heat network while a single trip is open, so its line is
        /// the thing you are looking at rather than one thread in the weave.
        /// The network stays faintly visible on purpose — it is the context
        /// that says which of your roads this drive used.
        private func refreshFocus(_ map: MKMapView) {
            for overlay in map.overlays {
                guard overlay is RoadFogOverlay,
                      let renderer = map.renderer(for: overlay) else { continue }
                let target = Self.fogAlpha(focused: selectedTripId != nil)
                guard renderer.alpha != target else { continue }
                renderer.alpha = target
                renderer.setNeedsDisplay()
            }
        }

        static func fogAlpha(focused: Bool) -> CGFloat { focused ? 0.22 : 1 }

        /// Region fills exist to show shape from far away. At street zoom the
        /// nearest border is off-screen and the fill is just a brown sheet over
        /// the roads you came to look at — including the SELECTED region's,
        /// which covered the whole screen until this stopped excluding it.
        ///
        /// Asks the map for its live renderers rather than keeping a
        /// dictionary of them: the old one was keyed by `ObjectIdentifier` and
        /// nothing ever removed an entry, so every overlay swap leaked a
        /// renderer — and once an overlay was deallocated its address could be
        /// handed to a new one, pointing the key at the wrong object.
        ///
        /// Only ever called when the zoom level actually changed. It used to
        /// run from `applyLevel` on every data sync, and `updateUIView` fires
        /// on every published change — so opening a card forced a redraw of
        /// every region polygon on screen for an alpha that had not moved.
        private func refreshRegionAlpha() {
            guard let map = mapView else { return }
            for overlay in map.overlays {
                guard let polygon = overlay as? RegionPolygon,
                      let renderer = map.renderer(for: polygon) else { continue }
                renderer.alpha = regionAlpha(for: polygon)
                renderer.setNeedsDisplay()
            }
        }

        private func regionAlpha(for polygon: RegionPolygon) -> CGFloat {
            guard level == .close else { return 1 }
            return polygon.style == .opened ? 0 : 0.35
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
            let renderer: MKOverlayRenderer
            if let region = overlay as? RegionPolygon {
                // Set here rather than patched afterwards: a polygon added
                // while zoomed in used to arrive at full opacity and only fade
                // on the next zoom change.
                let polygonRenderer = RegionPolygonRenderer(region: region)
                polygonRenderer.alpha = regionAlpha(for: region)
                renderer = polygonRenderer
            } else if let fog = overlay as? RoadFogOverlay {
                let fogRenderer = RoadFogRenderer(fog: fog)
                // A fog overlay installed while a trip is open must arrive
                // already dimmed, not at full strength until the next change.
                fogRenderer.alpha = Self.fogAlpha(focused: selectedTripId != nil)
                renderer = fogRenderer
            } else if let veil = overlay as? FogOfWarOverlay {
                renderer = FogOfWarRenderer(veil: veil)
            } else if let segment = overlay as? SpeedGradientPolyline {
                renderer = SelectedRouteRenderer(route: segment)
            } else {
                renderer = MKOverlayRenderer(overlay: overlay)
            }
            return renderer
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
            case let chip as CountryChipAnnotation:
                return mapView.dequeueReusableAnnotationView(
                    withIdentifier: CountryChipView.reuseID, for: chip)
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

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let newLevel = MapZoomLevel.of(mapView.region.span.latitudeDelta)
            guard newLevel != level else { return }
            level = newLevel
            applyLevel(mapView, animated: true)
            refreshRegionAlpha()
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
                // City dots and country chips are labels, not controls.
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

        // MARK: Helpers

        private static func polygons(
            for region: RegionAtlas.Region,
            style: RegionPolygon.Style
        ) -> [RegionPolygon] {
            region.rings.compactMap { ring in
                let count = ring.count / 2
                guard count > 2 else { return nil }
                var coords: [CLLocationCoordinate2D] = []
                coords.reserveCapacity(count)
                for i in 0..<count {
                    coords.append(CLLocationCoordinate2D(latitude: ring[2 * i], longitude: ring[2 * i + 1]))
                }
                let polygon = RegionPolygon(coordinates: coords, count: coords.count)
                polygon.regionId = region.id
                polygon.style = style
                return polygon
            }
        }

        private static func countryChips(
            for exploration: MapExploration,
            language: LanguageManager.Language
        ) -> [CountryChipAnnotation] {
            var byCountry: [String: [MapRegionStat]] = [:]
            for region in exploration.regions {
                byCountry[region.countryCode, default: []].append(region)
            }
            return byCountry.compactMap { code, regions in
                guard let name = RegionAtlas.shared.countryName(code, language) else { return nil }
                // Weight by km so the chip lands where you actually drove.
                let totalKm = max(regions.reduce(0) { $0 + $1.km }, 0.001)
                let lat = regions.reduce(0) { $0 + $1.center.latitude * $1.km } / totalKm
                let lon = regions.reduce(0) { $0 + $1.center.longitude * $1.km } / totalKm
                return CountryChipAnnotation(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    countryCode: code,
                    name: name
                )
            }
        }
    }
}
