import SwiftUI
import MapKit
import OSLog

/// Live-map render diagnostics. A blanket overlay teardown every frame is the
/// "route line blinks" fingerprint — we log only the pathological full rebuild
/// (`.notice`, exported), so the field signal is loud but the steady state quiet.
private let renderLog = Logger(subsystem: "com.triptrack", category: "render")

struct MapViewRepresentable: UIViewRepresentable {
    @Binding var userTrackingMode: MKUserTrackingMode
    var annotations: [MKPointAnnotation] = []
    var selectedAnnotation: MKPointAnnotation?
    var overlays: [MKOverlay] = []
    var bottomInset: CGFloat = 0
    @Binding var zoomDelta: Double
    var isRecording: Bool = false
    var onAnnotationSelected: ((MKPointAnnotation) -> Void)?
    var onCameraDistanceChanged: ((Double) -> Void)?
    var onVisibleRectChanged: ((MKMapRect) -> Void)?
    var onFogRendererCreated: ((FogVeilRenderer) -> Void)?
    /// Экранная вуаль встала в дерево карты (или ушла из него). Через неё
    /// модель ведёт прорезь у машины: растущая дыра — это маска на слое вуали,
    /// а не перерисовка тумана.
    var onScreenVeilChanged: ((FogVeilView?) -> Void)?
    /// Metal-туман встал в дерево карты (или ушёл из него). Через него модель
    /// ведёт ту же прорезь, что и через растровую вуаль: у той дыра — маска на
    /// слое, здесь — круг в шейдере. Два получателя одного и того же, и стоят
    /// они в соседних строках нарочно: разойдись они, прорезь на одном экране
    /// была бы в одном месте, а на откате — в другом.
    var onFogMetalChanged: ((FogMetalVeil?) -> Void)?
    /// Fires once when the map first finishes rendering. Lets the host clear its
    /// loading spinner from a real signal instead of a fragile timed Task.
    var onMapReady: (() -> Void)?
    /// Цвет машины, на которую пишется поездка — имя из гаража («red», …).
    /// `nil` — «Без транспорта»: маркер берёт цвет гаража по умолчанию.
    var carColorName: String? = nil
    /// Запись на паузе. Маркер гасит краску и надевает пилюлю с паузой —
    /// «остановился нарочно», сказанное на самой карте, а не только плашкой
    /// наверху экрана.
    var isPaused: Bool = false
    /// Нет принятого фикса дольше десяти секунд (`MapViewModel.gpsSignalStale`).
    /// Маркер теряет цвет совсем и наполовину растворяется: «я не знаю, где ты
    /// сейчас».
    var gpsSignalStale: Bool = false

    func makeUIView(context: Context) -> MKMapView {
        let mapView = VeilHostMapView()
        mapView.delegate = context.coordinator

        mapView.showsUserLocation = true
        mapView.userTrackingMode = userTrackingMode

        mapView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)

        // Initial camera. Prefer the system's cached fix (tight zoom). On a
        // first-ever launch there's no cached fix, so fall back to a country-
        // level camera instead of leaving the map at the blank grey world
        // origin (which reads as "still loading"); a live fix recenters via
        // follow mode once permission is granted.
        if let cachedLocation = CLLocationManager().location {
            mapView.camera = MKMapCamera(
                lookingAtCenter: cachedLocation.coordinate,
                fromDistance: 500, pitch: 0, heading: 0
            )
        } else {
            mapView.camera = MKMapCamera(
                lookingAtCenter: CLLocationCoordinate2D(latitude: 55.75, longitude: 37.62),
                fromDistance: 1_000_000, pitch: 0, heading: 0
            )
        }

        // Та же карта, что у Атласа и у экрана поездки: три экрана под ОДНОЙ
        // непрозрачной вуалью обязаны быть одной картой. До 0.7.0 здесь был
        // рельеф и стиль по солнцу — днём под чёрным туманом оказывалась
        // дневная рельефная карта, и внутри коридоров она была белой там, где
        // на двух других экранах серая. Конфигурация ставится ОДИН раз:
        // MapKit падает, если менять её у живой карты.
        mapView.preferredConfiguration = MKStandardMapConfiguration(
            elevationStyle: .flat, emphasisStyle: .muted
        )
        mapView.overrideUserInterfaceStyle = .dark

        mapView.showsCompass = false
        mapView.showsScale = true
        // Наклон запрещён на всей жизни карты: под экранной вуалью аффинная
        // матрица перспективу не выражает, и коридор уехал бы от дороги под
        // ним (`VeilFrame.residual`). Поворот при этом остаётся — на нём
        // держится режим «по курсу», и матрица его выражает точно.
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = true
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true

        let coordinator = context.coordinator
        coordinator.adoptMap(mapView)
        // Вуаль уходит вместе с экраном: два растра по запасу 2.2× и
        // `CADisplayLink` за кадром не живут.
        mapView.onWindowChange = { [weak coordinator, weak mapView] window in
            guard let coordinator, let mapView else { return }
            if window == nil {
                coordinator.veilSeat.detach()
            } else {
                coordinator.adoptMap(mapView)
            }
        }

        return mapView
    }

    /// Экран закрылся — вуаль уходит с ним.
    static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
        coordinator.veilSeat.detach()
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.adoptMap(mapView)

        // Tracking mode sync
        if !context.coordinator.suppressTrackingCallback,
           mapView.userTrackingMode != userTrackingMode {
            mapView.setUserTrackingMode(userTrackingMode, animated: true)
        }

        // Bottom inset
        let newInsets = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        if mapView.layoutMargins != newInsets {
            mapView.layoutMargins = newInsets
        }

        // Lock map interaction during recording (static mini-map)
        mapView.isScrollEnabled = !isRecording
        mapView.isZoomEnabled = !isRecording
        mapView.isRotateEnabled = !isRecording

        context.coordinator.applyCarState(on: mapView)

        // Diff annotations
        let existing = mapView.annotations.compactMap { $0 as? MKPointAnnotation }
        let toRemove = existing.filter { e in !annotations.contains(where: { $0 === e }) }
        if !toRemove.isEmpty { mapView.removeAnnotations(toRemove) }
        let toAdd = annotations.filter { n in !existing.contains(where: { $0 === n }) }
        if !toAdd.isEmpty { mapView.addAnnotations(toAdd) }

        // Sync selection
        if let selected = selectedAnnotation {
            if mapView.selectedAnnotations.first as? MKPointAnnotation !== selected {
                mapView.selectAnnotation(selected, animated: true)
            }
        } else {
            for ann in mapView.selectedAnnotations {
                mapView.deselectAnnotation(ann, animated: true)
            }
        }

        // Manual zoom buttons (idle mode only)
        if zoomDelta != 0, !isRecording {
            let coordinator = context.coordinator
            let camera = (mapView.camera.copy() as? MKMapCamera) ?? mapView.camera
            let factor = zoomDelta > 0 ? 0.5 : 2.0
            camera.centerCoordinateDistance = max(100, camera.centerCoordinateDistance * factor)
            let isFollowing = userTrackingMode != .none

            mapView.setCameraZoomRange(nil, animated: false)

            if isFollowing, mapView.userLocation.location != nil {
                camera.centerCoordinate = mapView.userLocation.coordinate
                coordinator.restoreTrackingWork?.cancel()

                if coordinator.savedTrackingMode == nil {
                    coordinator.savedTrackingMode = userTrackingMode
                    coordinator.suppressTrackingCallback = true
                    mapView.setUserTrackingMode(.none, animated: false)
                }

                mapView.camera = camera

                let modeToRestore = coordinator.savedTrackingMode ?? userTrackingMode
                let restoreWork = DispatchWorkItem { [weak coordinator] in
                    guard let coordinator, coordinator.savedTrackingMode != nil else { return }
                    let dist = mapView.camera.centerCoordinateDistance
                    let range = MKMapView.CameraZoomRange(
                        minCenterCoordinateDistance: dist,
                        maxCenterCoordinateDistance: dist
                    )
                    mapView.setCameraZoomRange(range, animated: false)
                    coordinator.suppressTrackingCallback = false
                    coordinator.savedTrackingMode = nil
                    mapView.setUserTrackingMode(modeToRestore, animated: true)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        mapView.setCameraZoomRange(nil, animated: false)
                    }
                }
                coordinator.restoreTrackingWork = restoreWork
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: restoreWork)
            } else {
                UIView.animate(withDuration: 0.3) {
                    mapView.camera = camera
                }
            }

            DispatchQueue.main.async { self.zoomDelta = 0 }
        }

        // Diff overlays surgically (mirrors the annotation diff above). The old
        // code removed ALL overlays and re-added ALL of them whenever the
        // ObjectIdentifier set differed — and the glowing head segment
        // republishes at up to 60fps with a fresh identity, so that compare
        // ALWAYS differed and tore down + re-added the unchanged route polyline
        // every frame, which MapKit rendered as the orange line blinking. Now we
        // only touch overlays that actually changed; the route line stays put.
        let existingOverlays = mapView.overlays
        let toRemoveOverlays = existingOverlays.filter { e in !overlays.contains(where: { $0 === e }) }
        if !toRemoveOverlays.isEmpty { mapView.removeOverlays(toRemoveOverlays) }
        for overlay in overlays where !existingOverlays.contains(where: { $0 === overlay }) {
            // Deterministic z-order so it can't depend on which layer was
            // re-added last. The route line is rebuilt every 0.5s and would
            // otherwise come back ON TOP of the glowing head; the head is
            // appended (= topmost), the route inserted right above the veil.
            if let fog = overlay as? FogVeilOverlay {
                // Экранная вуаль на месте — плиточный оверлей на карту не
                // кладём вовсе: рисовали бы одно и то же дважды, причём нижнее
                // всё равно не видно. Слой при этом отдаём ей — он тот же.
                if context.coordinator.veilSeat.isAttached {
                    context.coordinator.handOverFog(fog)
                    continue
                }
                // Непрозрачная вуаль обязана лежать ВЫШЕ подписей Apple
                // (иначе названия городов висят поверх темноты) и НИЖЕ всего
                // своего. Поэтому уровень у всех трёх один, а порядок внутри
                // него задан явно: вуаль в самый низ, трек сразу над ней,
                // светящаяся голова — сверху.
                mapView.insertOverlay(overlay, at: 0, level: .aboveLabels)
            } else if overlay is GlowingHeadOverlay {
                mapView.addOverlay(overlay, level: .aboveLabels)
            } else {
                let veils = mapView.overlays(in: .aboveLabels)
                    .filter { $0 is FogVeilOverlay }.count
                mapView.insertOverlay(overlay, at: veils, level: .aboveLabels)
            }
        }
        // Regression alarm: a FULL teardown of a multi-overlay set DURING
        // recording is the blink fingerprint. Gated on isRecording so a normal
        // trip-stop clear (fog-only swap, recording=false) doesn't cry wolf.
        if self.isRecording, existingOverlays.count > 1,
           toRemoveOverlays.count == existingOverlays.count {
            context.coordinator.logFirstFullOverlayRebuild(
                removed: toRemoveOverlays.count, added: overlays.count
            )
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable
        var suppressTrackingCallback = false
        var restoreTrackingWork: DispatchWorkItem?
        var savedTrackingMode: MKUserTrackingMode?
        var didSendInitialRect = false
        private var didLogFullOverlayRebuild = false

        /// Keep the regression signal without filling the recording archive on
        /// every map update and evicting GPS errors or pause/stop diagnostics.
        func logFirstFullOverlayRebuild(removed: Int, added: Int) {
            guard !didLogFullOverlayRebuild else { return }
            didLogFullOverlayRebuild = true
            renderLog.notice("overlays full rebuild (first for this map): removed=\(removed, privacy: .public) new=\(added, privacy: .public)")
        }

        /// Посадка экранной вуали — та же, что у «Атласа» и у экрана поездки.
        ///
        /// Место — ПОД контейнером оверлеев: трек, светящаяся голова и линия
        /// маршрута рисуются `MKOverlayRenderer`-ом, и вуаль выше них спрятала
        /// бы запись под собой. Запас 2.2×, потому что карта на записи
        /// ВРАЩАЕТСЯ («по курсу»), а с поворотом меняет форму и та коробка, по
        /// которой считается растр.
        let veilSeat = VeilSeat(margin: FogVeilView.rotatingMargin, seat: .aboveBaseMap)
        /// Metal-туман: мглу рисует он, растровой вуали остаётся её вектор
        /// (`vectorOnly`). Садится ПОД вуаль, то есть тоже ниже контейнера
        /// оверлеев: трек, светящаяся голова и линия маршрута рисуются
        /// `MKOverlayRenderer`-ом, и мгла выше них спрятала бы саму запись.
        let fogMetal = FogMetalSeat()
        private weak var mapRef: MKMapView?

        init(_ parent: MapViewRepresentable) {
            self.parent = parent
            super.init()
            // Мглу рисует GPU — вуали остаётся её вектор. Ставится ЗДЕСЬ, а не
            // при посадке: слой доезжает до вуали оверлеем модели, и растр,
            // заказанный раньше посадки, был бы нарисован зря.
            veilSeat.veil.vectorOnly = fogMetal.isActive
            veilSeat.onAttached = { [weak self] in self?.screenVeilTookOver() }
            veilSeat.onDetached = { [weak self] in self?.screenVeilStoodDown() }
        }

        /// Карта готова — запоминаем её и сажаем вуаль. Идемпотентно.
        func adoptMap(_ mapView: MKMapView) {
            mapRef = mapView
            veilSeat.attach(to: mapView)
            seatFogMetal()
        }

        /// Metal-слой садится под растровую вуаль — и ТЕМ ЖЕ зовом
        /// возвращается, если потерял место: `FogVeilView.verifySeating`
        /// возвращает в дерево СЕБЯ и, вернувшись удачно, молчит, — то есть о
        /// пересборке сабвью MapKit Metal-слою не сказал бы никто, и запись
        /// осталась бы поверх ГОЛОЙ карты Apple.
        private func seatFogMetal() {
            guard let map = mapRef else { return }
            fogMetal.follow(veilSeat, on: map)
        }

        /// Какой оверлей тумана уже отдан вуали.
        ///
        /// Без этой памяти `setLayer` зовётся на КАЖДОМ `updateUIView`, а
        /// светящаяся голова переиздаёт оверлеи с новой идентичностью до
        /// шестидесяти раз в секунду: плиточного оверлея на карте нет (его и не
        /// кладут), поэтому диффу оверлеев сравнивать не с чем. `setLayer` на
        /// том же слое выходит рано, но подпись слоя он считает ДО выхода —
        /// массив по всем тонким полилиниям открытого мира, шестьдесят раз в
        /// секунду на главном потоке.
        private weak var handedFog: FogVeilOverlay?

        /// Отдать вуали слой этого оверлея — ровно один раз на оверлей.
        func handOverFog(_ fog: FogVeilOverlay) {
            guard handedFog !== fog else { return }
            handedFog = fog
            // Обоим сразу и в одной строке: мглу рисует метал, жилку — вуаль.
            veilSeat.veil.setLayer(fog.layer)
            fogMetal.setLayer(fog.layer)
        }

        /// Вуаль встала: снимаем плиточный оверлей и отдаём ей тот же слой.
        private func screenVeilTookOver() {
            if let map = mapRef {
                map.removeOverlays(map.overlays.filter { $0 is FogVeilOverlay })
            }
            seatFogMetal()
            if let fog = parent.overlays.compactMap({ $0 as? FogVeilOverlay }).first {
                handOverFog(fog)
            }
            veilSeat.startTracking(tail: 1.5)
            fogMetal.startTracking(tail: 1.5)
            parent.onScreenVeilChanged?(veilSeat.veil)
            parent.onFogMetalChanged?(fogMetal.veil)
        }

        /// Вуаль ушла: туман возвращается плиточному рендереру, иначе карта
        /// осталась бы голой.
        private func screenVeilStoodDown() {
            // Вуаль ушла — отданное ей забыто: сядет заново, слой надо отдать
            // снова.
            handedFog = nil
            fogMetal.unseat()
            parent.onScreenVeilChanged?(nil)
            parent.onFogMetalChanged?(nil)
            guard let map = mapRef,
                  !map.overlays.contains(where: { $0 is FogVeilOverlay }),
                  let fog = parent.overlays.compactMap({ $0 as? FogVeilOverlay }).first
            else { return }
            map.insertOverlay(fog, at: 0, level: .aboveLabels)
        }

        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            guard !didSendInitialRect else { return }
            didSendInitialRect = true
            let rect = mapView.visibleMapRect
            DispatchQueue.main.async {
                self.parent.onVisibleRectChanged?(rect)
                // Real "the map is up" signal — clears the host's loading spinner.
                self.parent.onMapReady?()
            }
        }

        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            guard !suppressTrackingCallback else { return }
            DispatchQueue.main.async {
                if self.parent.userTrackingMode != mode {
                    self.parent.userTrackingMode = mode
                }
            }
        }

        /// Курс маркера по земле, [0, 360). Держим в координаторе: вид MapKit
        /// вправе выбросить и создать заново.
        private var carCourse: Double = 0
        /// Пока курса не было ни разу, держать нечего — первый достоверный
        /// ставится без доводки.
        private var carHasCourse = false
        private var lastCourseTick: CFTimeInterval = 0
        /// Радиус круга точности в МЕТРАХ, прямо от CoreLocation. `nil` — фикса
        /// нет, и круг обещал бы точность, которой не существует.
        private var accuracyMeters: Double?
        /// Полуугол конуса «еду примерно туда» — или `nil`, когда курсу верим.
        private var coneHalfAngle: Double?

        /// Всё, что маркер показывает кроме курса.
        ///
        /// Пауза старше потери сигнала: в подземном паркинге верны оба, но
        /// человек нажал паузу сам, и сказать ему «сигнал потерян» значит
        /// объяснить его же решение поломкой. Тем же порядком идут и баннеры
        /// наверху экрана.
        private var carState: MapCarMarker.State {
            let mood: MapCarMarker.Mood
            if parent.isRecording && parent.isPaused {
                mood = .paused
            } else if parent.isRecording && parent.gpsSignalStale {
                mood = .lost
            } else {
                mood = .normal
            }
            return MapCarMarker.State(
                colorName: parent.carColorName,
                accuracyMeters: accuracyMeters,
                // На паузе и без сигнала конус не рисуется: он про «еду
                // примерно туда», а никто никуда не едет.
                coneHalfAngle: mood == .normal ? coneHalfAngle : nil,
                // Пульс — «сигнал живой», и только на записи. В простое карта
                // ничего не пишет, и пульсировать ей не о чем.
                pulses: parent.isRecording && mood == .normal,
                mood: mood
            )
        }

        func applyCarState(on mapView: MKMapView) {
            carView(on: mapView)?.setState(carState)
        }

        private func carView(on mapView: MKMapView) -> MapCarAnnotationView? {
            mapView.view(for: mapView.userLocation) as? MapCarAnnotationView
        }

        /// Куда смотрит машинка на живой записи.
        ///
        /// Курс берём у CoreLocation напрямую — у него он с доплера, то есть
        /// про движение, а не про разницу двух зашумлённых точек. Ворота — в
        /// `CarHeadingPolicy`: не прошли, значит держим последний достоверный
        /// угол, а не подставляем север.
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard let location = userLocation.location else { return }
            let now = CACurrentMediaTime()
            let dt = lastCourseTick > 0 ? min(now - lastCourseTick, 2) : 1
            lastCourseTick = now

            let target = CarHeadingPolicy.liveCourse(
                course: location.course,
                courseAccuracy: location.courseAccuracy,
                rawSpeed: location.speed
            )
            if !carHasCourse, let target {
                carCourse = target
                carHasCourse = true
            } else {
                // Reduce Motion: сам поворот остаётся — это информация, и
                // системная стрелка курса тоже не выключается. Уходит доводка.
                carCourse = CarHeadingPolicy.smoothed(
                    current: carCourse, target: target, dt: dt,
                    instant: UIAccessibility.isReduceMotionEnabled
                )
            }
            // Круг точности и конус приезжают тем же фиксом, что и курс:
            // спрашивать их у модели значило бы завести второй счёт того же
            // самого, и однажды он разошёлся бы с первым.
            accuracyMeters = location.horizontalAccuracy > 0 ? location.horizontalAccuracy : nil
            coneHalfAngle = CarHeadingPolicy.coneHalfAngle(
                courseAccuracy: location.courseAccuracy, rawSpeed: location.speed
            )
            let view = carView(on: mapView)
            view?.setState(carState)
            view?.setScale(metersPerPoint: mapView.metersPerScreenPoint)
            view?.apply(
                course: carCourse, cameraHeading: mapView.camera.heading, animated: true
            )
        }

        /// Карта повернулась — сама (режим «по курсу») или пальцами. Экранный
        /// угол маркера считается от поворота камеры, и без этого нос
        /// отвязывается от дороги под собой.
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            veilSeat.startTracking()
            fogMetal.startTracking()
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            // Камера на записи едет сама, без `regionWillChange`: машина
            // тянет её за собой каждым фиксом, а в режиме «по курсу» ещё и
            // крутит. Здесь и заводится привязка растра.
            veilSeat.startTracking()
            fogMetal.startTracking()
            guard let view = carView(on: mapView) else { return }
            view.applyScreenAngle(cameraHeading: mapView.camera.heading)
            // Тем же жестом меняется масштаб — отсюда круг точности, конус и
            // решение схлопнуться в точку узнают, сколько метров в пункте.
            view.setScale(metersPerPoint: mapView.metersPerScreenPoint)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Машинка — маркер «это я», и экран записи был последним, кто
            // отдавал эту работу синему кружку MapKit. Тот же вид, что у
            // реплея: вид сверху, повёрнутый на курс. Ассета нет — падаем на
            // штатный кружок, а не на пустое место.
            if annotation is MKUserLocation {
                guard MapCarMarker.image(colorName: parent.carColorName) != nil else { return nil }
                let id = MapCarAnnotationView.reuseIdentifier
                let carView = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MapCarAnnotationView
                    ?? MapCarAnnotationView(annotation: annotation, reuseIdentifier: id)
                carView.annotation = annotation
                // Nothing to open on tap; selectable, it would swallow taps
                // meant for the map under it.
                carView.isEnabled = false
                carView.setState(carState)
                carView.setScale(metersPerPoint: mapView.metersPerScreenPoint)
                carView.apply(course: carCourse, cameraHeading: mapView.camera.heading)
                carView.layer.zPosition = 1000
                return carView
            }

            let identifier = "SearchPin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)

            view.annotation = annotation
            // Was MapKit's stock blue. On a screen whose whole surface is a
            // map, the one saturated object on it was the one thing in the app
            // wearing somebody else's colour.
            view.markerTintColor = UIColor(AppTheme.accent)
            view.glyphImage = UIImage(systemName: "mappin")
            view.canShowCallout = true
            return view
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Камера встала — один ЧЁТКИЙ кадр под новый масштаб.
            veilSeat.settle(on: mapView)
            // Металу заказывать нечего: он и так рисует каждый кадр, ему нужен
            // только хвост — доехать инерцию и погаснуть.
            fogMetal.extendTracking(tail: 0.6)
            let distance = mapView.camera.centerCoordinateDistance
            let cameraCallback = parent.onCameraDistanceChanged
            let rectCallback = parent.onVisibleRectChanged
            let visibleRect = mapView.visibleMapRect
            DispatchQueue.main.async {
                cameraCallback?(distance)
                rectCallback?(visibleRect)
            }
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let point = view.annotation as? MKPointAnnotation else { return }
            parent.onAnnotationSelected?(point)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let veil = overlay as? FogVeilOverlay {
                let renderer = FogVeilRenderer(veil: veil)
                DispatchQueue.main.async { [weak self] in
                    self?.parent.onFogRendererCreated?(renderer)
                }
                return renderer
            }
            if let headOverlay = overlay as? GlowingHeadOverlay {
                return GlowingHeadRenderer(overlay: headOverlay)
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 194/255, green: 69/255, blue: 43/255, alpha: 0.8)
                renderer.lineWidth = 4
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
