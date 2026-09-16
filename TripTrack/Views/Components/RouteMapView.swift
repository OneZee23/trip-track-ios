import SwiftUI
import MapKit

// MARK: - SpeedPolyline

/// Custom MKPolyline subclass that carries the speed value for color mapping.
final class SpeedPolyline: MKPolyline {
    var speed: Double = 0 // m/s

    /// Доля маршрута, на которой этот отрезок КОНЧАЕТСЯ, от 0 до 1.
    ///
    /// Нужна воспроизведению: пройденное показывается полной яркостью, а
    /// непройденное приглушается — и решается это сравнением двух долей.
    /// Именно доля, а не метры и не индекс: отрезки строятся по упрощённому
    /// маршруту, а машина едет по плотному, длины у них отличаются на доли
    /// процента, а номера точек не совпадают вовсе. Доля — единственная
    /// величина, одинаковая у обоих.
    var endFraction: Double = 1
}

/// Линия маршрута с тёмной обводкой — для карты под туманом.
///
/// Обводка не украшение: внутри прочищенного коридора лежит живая карта Apple,
/// и градиент скорости, положенный прямо на неё, сливается с жёлтым шоссе под
/// собой. Тем же приёмом и тем же цветом обведена выбранная жилка Атласа
/// (`RouteVeinRenderer.casingColor`) — две карты в одном приложении обязаны
/// рисовать маршрут одинаково.
///
/// Путь собирается САМ, а не берётся из `path` родителя: `MKOverlayPathRenderer`
/// создаёт его лениво, и полагаться на момент, когда он появится, значит
/// однажды нарисовать обводку в пустоту.
///
/// И собирается он ДО первой отрисовки, явным вызовом `buildCasing()` — по той
/// же причине, по которой `FogVeilRenderer` не строит индекс в `draw`: MapKit
/// рисует тайлы на нескольких потоках сразу.
final class CasedPolylineRenderer: MKPolylineRenderer {
    /// Насколько обводка шире линии, в экранных точках (по 1 pt на сторону).
    static let casingExtra: CGFloat = 2.0

    /// `var` и не `let`: трансформ `point(for:)` появляется только после
    /// `super.init`, а трогать `self` до инициализации всех полей нельзя.
    private var casingPath = CGMutablePath()

    /// Собрать обводку. Зовётся тем, кто создал рендерер, — на ГЛАВНОМ потоке,
    /// до первой отрисовки (`Coordinator.routeRenderer`).
    ///
    /// Не `lazy var` и не `init`. `lazy var` в Swift не синхронизирован, а
    /// `draw` MapKit зовёт на нескольких потоках сразу — два тайла вошли бы в
    /// инициализатор вдвоём. Свой `init` тоже не годится: `init(polyline:)` у
    /// MapKit зовёт `init(overlay:)` через `objc`, и подкласс, переопределивший
    /// одно из двух, падает на ловушке «use of unimplemented initializer» в
    /// `makeUIView` (проверено падением 15 сен).
    func buildCasing() {
        let line = polyline
        guard line.pointCount > 1 else { return }
        let path = CGMutablePath()
        let points = line.points()
        path.move(to: point(for: points[0]))
        for i in 1..<line.pointCount { path.addLine(to: point(for: points[i])) }
        casingPath = path
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.beginPath()
        context.addPath(casingPath)
        context.setLineWidth((lineWidth + Self.casingExtra) / zoomScale)
        context.setStrokeColor(RouteVeinRenderer.casingColor.cgColor)
        context.strokePath()
        super.draw(mapRect, zoomScale: zoomScale, in: context)
    }
}


/// Annotation that the renderer recognises as the moving "play head" —
/// shown as the pixel-car asset travelling along the route.
/// Снимок, стоящий на маршруте там, где он сделан.
final class PhotoAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let photoId: UUID
    let image: UIImage?
    /// NSObject уже владеет `accessibilityLabel` — своё имя.
    let voiceLabel: String

    init(coordinate: CLLocationCoordinate2D, photoId: UUID, image: UIImage?, accessibilityLabel: String = "") {
        self.coordinate = coordinate
        self.photoId = photoId
        self.image = image
        self.voiceLabel = accessibilityLabel
    }
}

/// Отметка на маршруте в том виде, в каком её рисует карта.
///
/// Карта не знает про `TripCheckpoint`: ей отдают готовую подпись и готовую
/// миниатюру. Подпись форматирует экран (он знает язык), миниатюру грузит
/// экран (аннотация берёт картинку синхронно, и чтение с диска внутри карты
/// подвесило бы её).
struct CheckpointMarker: Equatable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let number: Int
    /// Имя от человека или от геокодера: «Джубга». Пустое — покажем номер.
    let name: String?
    /// «1:30 · 128 км».
    let reading: String
    /// Обложка — прикреплённый или ближайший по времени снимок, уже уменьшенный.
    let image: UIImage?
    /// Сколько всего снимков у отметки. Больше одного — на карточке «+N».
    var photoCount: Int = 0
    /// Когда отметка была поставлена — по ней реплей знает, где задержаться.
    var timestamp: Date = .distantPast
    /// Снимок-обложка — по нему карточка выбранной отметки открывает просмотр.
    var coverPhotoId: UUID?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Насколько подробно рисовать отметку.
///
/// На маленькой карте-герое подписи налезали бы друг на друга уже при трёх
/// отметках в одном районе; там достаточно кружка со снимком или номером. На
/// полноэкранной карте подпись — главное: ролик «до моря за полтора часа»
/// снимается именно с неё, и зритель должен прочесть время, не зумя.
enum CheckpointMarkerStyle {
    case compact
    case labelled
}

/// Точка, куда ВСТАНЕТ отметка, если человек подтвердит. Ещё не отметка.
///
/// Появляется в момент касания, до карточки с числами: без неё палец по карте
/// давал ответ «2:14 · 143 км» и ни намёка, где именно на маршруте это место.
/// Отклик обязан быть под пальцем, а не внизу экрана.
struct CheckpointCandidate: Equatable {
    let id: Int
    let latitude: Double
    let longitude: Double
    /// Номер, когда кандидатов несколько (дорога «туда и обратно»), чтобы
    /// точка на карте и строка в карточке читались как одно.
    let number: Int?
    /// Что скажет VoiceOver. Карта языка не знает — текст готовит экран.
    var accessibilityLabel: String = ""

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

final class CheckpointCandidateAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let candidate: CheckpointCandidate

    init(candidate: CheckpointCandidate) {
        self.coordinate = candidate.coordinate
        self.candidate = candidate
    }
}

final class CheckpointAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let marker: CheckpointMarker
    let style: CheckpointMarkerStyle

    init(marker: CheckpointMarker, style: CheckpointMarkerStyle) {
        self.coordinate = marker.coordinate
        self.marker = marker
        self.style = style
    }
}

final class PlaybackCarAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
}

struct PhotoPin: Equatable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let image: UIImage?
    /// Что скажет VoiceOver — экран готовит на своём языке.
    var accessibilityLabel: String = ""
    /// «1 ч 19 мин · 106 км» — сколько до этого кадра от старта. Готовит
    /// экран (у него трек и язык), карточка предпросмотра только печатает.
    /// `nil` — кадр не встал на трек, и сказать нечего.
    var reading: String? = nil
    /// Имя файла в `Documents/TripPhotos` — по нему карточка предпросмотра
    /// берёт ступень 600 pt, а не тянет ту же булавку в 80 pt крупнее.
    var filename: String? = nil

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct RouteMapView: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]
    var speeds: [Double] = []
    var isInteractive: Bool = false
    /// Отметки на маршруте — с подписью и снимком.
    var checkpointMarkers: [CheckpointMarker] = []
    var checkpointMarkerStyle: CheckpointMarkerStyle = .compact
    /// Снимки, расставленные по маршруту. Миниатюры готовит вызывающий:
    /// `MKAnnotationView` берёт картинку синхронно, и грузить её здесь значило
    /// бы держать карту в ожидании диска.
    var photoPins: [PhotoPin] = []
    /// Нажатие на снимок на карте.
    var onPhotoTap: ((UUID) -> Void)?
    /// Нажатие на отметку. Карта только сообщает — карточку рисует экран.
    var onCheckpointTap: ((UUID) -> Void)?
    /// Точка, которую надо показать: карта подъезжает, если та под карточкой
    /// или за краем. Меняется — подъезжает снова; та же — не трогает камеру.
    var focusCoordinate: CLLocationCoordinate2D?
    /// Кандидаты в отметки — точки под пальцем до подтверждения.
    var checkpointCandidates: [CheckpointCandidate] = []
    /// Палец по карте. Отдаёт координату и масштаб (метров в одном пункте
    /// экрана): радиус попадания должен быть про палец, а не про метры —
    /// на обзорном зуме 120 м это точка, на дворовом — пол-экрана.
    var onRouteTap: ((CLLocationCoordinate2D, Double) -> Void)?
    var fogCutoffDate: Date?
    /// Whether the personal fog-of-war belongs on this map at all.
    ///
    /// A nil `fogCutoffDate` used to mean "fog from EVERYTHING I have ever
    /// visited", which is right for my own maps and badly wrong for someone
    /// else's trip: their route came out dimmed by MY exploration — and since
    /// I have never driven where they drove, that meant dimmed end to end.
    /// The two meanings needed separating; this is the one that says "no fog".
    var showsFog: Bool = true
    /// When true, disable gap-splitting. Preview polylines from the social
    /// feed are already RDP-simplified — points can be several km apart,
    /// which the 1 km gap threshold treats as discontinuities and leaves the
    /// map with zero drawable segments (so no bounding rect, so no zoom).
    var treatAsPreview: Bool = false
    /// Цвет машины этой поездки — имя из гаража («red», «silver», …). `nil`
    /// значит «без транспорта»: маркер всё равно рисуется, цветом гаража по
    /// умолчанию. Красится только машинка реплея — на карте без реплея её нет.
    var carColorName: String? = nil
    /// Bumped by the caller's «+» / «−» buttons. Only the CHANGE matters — the
    /// coordinator remembers the last value it applied, so an unrelated
    /// re-render never re-zooms the map under the user's fingers.
    var zoomTick: Int = 0
    /// Interpolated car position for the current playback frame, or `nil`
    /// when not playing. Pre-computed by `RoutePlaybackController` and
    /// passed through here — the view does not interpolate, it only
    /// renders. Driven by CADisplayLink at the display's native rate.
    var playbackCarCoord: CLLocationCoordinate2D? = nil
    /// Index of the last original GPS coordinate the playback head has
    /// passed. The view checks this against its remembered last value
    /// before swapping the trail polyline overlay — replacing the
    /// overlay every frame is the #1 source of MapKit frame drops, so
    /// we only do it when the trail tip actually advances to a new
    /// real waypoint.
    var playbackTrailIndex: Int = -1
    /// Coordinates the PLAYBACK walks, when they differ from the ones the
    /// route is drawn from. The trail is rebuilt from scratch every time the
    /// head passes a waypoint, so a raw ten-hour track (tens of thousands of
    /// points) turns that into tens of thousands of rebuilds of an
    /// ever-longer polyline. Drawing wants every point; playback wants a few
    /// hundred.
    var playbackCoords: [CLLocationCoordinate2D]? = nil
    /// Camera rides with the playback head instead of framing the whole route.
    /// The car then sits at a FIXED point on screen — the middle — which is
    /// what lets the replay draw a speed bubble over it without projecting
    /// coordinates into view space itself.
    var playbackFollow: Bool = false
    /// Metres across the map while following.
    var playbackFollowSpan: Double = 1400
    /// Padding used when framing the whole route. The replay needs a wider
    /// bottom margin than the previews do — its transport controls sit there.
    var fitInsets: UIEdgeInsets?
    /// Карта, пережившая своё представление. Непустой хост означает: не
    /// создавать `MKMapView` заново, а забрать готовую — см. `TripMapHost`.
    var host: TripMapHost? = nil
    /// Меняется — карта заново вписывает весь маршрут в свои НЫНЕШНИЕ
    /// границы. Важен только факт изменения: раскрытие на полный экран
    /// бумает его один раз, когда кадр уже приехал.
    var fitTick: Int = 0

    /// На каком уровне лежит сама линия маршрута.
    ///
    /// Под непрозрачной вуалью выбора нет: вуаль обязана быть выше подписей
    /// (иначе названия городов висят поверх темноты), а маршрут — выше вуали,
    /// иначе поездки на экране поездки просто нет. Поэтому со своим туманом
    /// оба уезжают на `.aboveLabels`, и порядок внутри уровня держит вставка
    /// вуали в самый низ (`installFog`). Без тумана (чужая поездка,
    /// путешествие) всё остаётся ровно как было.
    private var routeLevel: MKOverlayLevel { showsFog ? .aboveLabels : .aboveRoads }

    private static let gapThreshold = GeometryUtils.defaultGapThreshold

    /// Smallest rect the preview will zoom to, ~400 m across.
    ///
    /// A trip recorded standing still collapses to a rect of almost no size,
    /// and `setVisibleMapRect` honours it literally: the camera goes to its
    /// maximum zoom, past the level any tiles exist for, and the preview comes
    /// out an empty grey rectangle. A floor keeps the surrounding streets in
    /// frame, so a stationary trip looks like a place instead of a bug.
    private static let minimumSpanMetres: Double = 400

    static func floored(_ rect: MKMapRect) -> MKMapRect {
        let centre = MKMapPoint(x: rect.midX, y: rect.midY)
        let pointsPerMetre = MKMapPointsPerMeterAtLatitude(centre.coordinate.latitude)
        let minimum = minimumSpanMetres * pointsPerMetre
        guard rect.size.width < minimum || rect.size.height < minimum else { return rect }
        let width = max(rect.size.width, minimum)
        let height = max(rect.size.height, minimum)
        return MKMapRect(x: centre.x - width / 2, y: centre.y - height / 2,
                         width: width, height: height)
    }

    func makeUIView(context: Context) -> MKMapView {
        // Карта с хостом строится ОДИН раз за жизнь экрана поездки: герой и
        // полноэкранная раскладка — два представления одной и той же карты,
        // и второй разрез маршрута по скорости здесь не нужен никому.
        if let host, host.mapView != nil {
            let existing = host.map(orMake: { MKMapView() })
            host.retain()
            context.coordinator.adoptMap(existing)
            applyInteractivity(to: existing)
            applyLayoutMargins(to: existing, coordinator: context.coordinator)
            return existing
        }
        // Своя карта только под туманом: ей нужен сигнал об уходе экрана, а у
        // `UIViewRepresentable` вью-контроллера нет. Чужой поездке и
        // путешествию (`showsFog == false`) вуали не достаётся вовсе — там и
        // подменять нечего.
        let make = { context.coordinator.veilSeat == nil ? MKMapView() : VeilHostMapView() }
        let mapView: MKMapView
        if let host {
            mapView = host.map(orMake: make)
            host.retain()
            context.coordinator.host = host
        } else {
            mapView = make()
        }
        mapView.delegate = context.coordinator
        context.coordinator.showsFog = showsFog
        mapView.showsUserLocation = false
        applyInteractivity(to: mapView)
        mapView.showsCompass = false
        mapView.showsScale = false
        // Карта СВОЕЙ поездки (та, над которой лежит туман) — всегда ночная и
        // приглушённая, ровно та же конфигурация, что у Атласа. До 0.7.0 здесь
        // была светлая кремовая карта с толстым градиентом скорости, и рядом с
        // ночной вкладкой «Карта» это читалось как два разных приложения.
        // Конфигурация ставится ОДИН раз, здесь: MapKit падает, если менять её
        // у живой карты.
        if showsFog {
            mapView.preferredConfiguration = MKStandardMapConfiguration(
                elevationStyle: .flat, emphasisStyle: .muted
            )
            mapView.overrideUserInterfaceStyle = .dark
        } else {
            // `preferredConfiguration` ставится ОДИН раз (MapKit падает при
            // смене у живой карты), а карту с хостом строит герой, который
            // пальцев не принимает. Полный экран у неё впереди по
            // определению — значит и рельеф берётся сразу его, как и
            // поворотный запас растра у вуали.
            mapView.preferredConfiguration = MKStandardMapConfiguration(
                elevationStyle: (isInteractive || host != nil) ? .realistic : .flat
            )
        }
        // Apple requires the Maps attribution to stay visible, and it is laid
        // out against these margins. Without this the replay's transport row
        // sits right on top of it.
        applyLayoutMargins(to: mapView, coordinator: context.coordinator)

        // Вуаль садится, когда карта попадает в окно, и уходит вместе с ним:
        // `dismantleUIView` приходит не всегда (SwiftUI вправе придержать
        // представление), а два растра и `CADisplayLink` за кадром не живут.
        let coordinator = context.coordinator
        coordinator.adoptMap(mapView)
        if let host = mapView as? VeilHostMapView {
            host.onWindowChange = { [weak coordinator, weak host] window in
                guard let coordinator, let host else { return }
                if window == nil {
                    // Карта с хостом переезжает между слотом героя и
                    // полноэкранной раскладкой, и на этом переезде окно на
                    // мгновение становится пустым. Снимать вуаль сразу
                    // значило бы пересаживать её на каждое раскрытие —
                    // ровно то, чего переезд и должен избежать.
                    //
                    // Но и просто выйти нельзя: `dismantleUIView` SwiftUI
                    // вправе придержать, и тогда у вуали не осталось бы ни
                    // одной двери. Переспрашиваем на следующем витке: карта,
                    // которая к нему так и не вернулась в окно, ушла
                    // по-настоящему.
                    guard !coordinator.isHosted else {
                        Task { @MainActor [weak coordinator, weak host] in
                            guard let coordinator, let host, host.window == nil else { return }
                            coordinator.host?.release()
                        }
                        return
                    }
                    coordinator.veilSeat?.detach()
                } else {
                    coordinator.adoptMap(host)
                }
            }
        }

        if coordinates.count >= 2 {
            // Split into continuous segments first, then simplify each.
            // Preview polylines are treated as one solid segment — their
            // points are sparsely sampled so gap detection would shred
            // them into singleton segments that render as nothing.
            let segments: [([CLLocationCoordinate2D], [Double])]
            if treatAsPreview {
                segments = [(coordinates, speeds.count == coordinates.count ? speeds : [])]
            } else if speeds.count == coordinates.count {
                segments = Self.splitIntoSegments(coordinates, speeds: speeds, gapThreshold: Self.gapThreshold)
            } else {
                segments = Self.splitIntoSegments(coordinates, speeds: [], gapThreshold: Self.gapThreshold)
            }

            var unionRect: MKMapRect = .null
            let epsilon = Self.drawEpsilon
            // Отрезки скорости в порядке маршрута — воспроизведение гасит
            // ими непройденное, вместо того чтобы подкладывать белую линию.
            var speedRun: [SpeedPolyline] = []
            var runMetres: [Double] = []
            var runTotal: Double = 0

            for (segCoords, segSpeeds) in segments {
                guard segCoords.count >= 2 else { continue }

                if segSpeeds.count == segCoords.count {
                    let simplified = Self.simplifyWithSpeeds(segCoords, speeds: segSpeeds, epsilon: epsilon)
                    // Group consecutive points in the same speed zone into single polylines
                    let grouped = Self.groupBySpeedZone(simplified)
                    for group in grouped {
                        var coords = group.coords
                        let poly = SpeedPolyline(coordinates: &coords, count: coords.count)
                        poly.speed = group.speed
                        mapView.addOverlay(poly, level: routeLevel)
                        unionRect = unionRect.union(poly.boundingMapRect)
                        runTotal += GeometryUtils.polylineLength(group.coords)
                        speedRun.append(poly)
                        runMetres.append(runTotal)
                    }
                } else {
                    let simplified = GeometryUtils.simplifyRDP(segCoords, epsilon: epsilon)
                    var mutable = simplified
                    let polyline = MKPolyline(coordinates: &mutable, count: mutable.count)
                    mapView.addOverlay(polyline, level: routeLevel)
                    unionRect = unionRect.union(polyline.boundingMapRect)
                }
            }

            // Доли считаются ПОСЛЕ прохода: полная длина известна только в
            // конце. Разрывы записи в сумму входят — машина их «проезжает»
            // тоже, и без этого прогресс убегал бы вперёд после каждой дыры.
            if runTotal > 0 {
                for (i, poly) in speedRun.enumerated() {
                    poly.endFraction = runMetres[i] / runTotal
                }
            }
            context.coordinator.speedRun = speedRun

            if !unionRect.isNull {
                let insets = fitInsets ?? UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30)
                // Remembered so the replay can come back to the whole route
                // after following the car around.
                context.coordinator.overviewRect = unionRect
                context.coordinator.overviewInsets = insets
                mapView.setVisibleMapRect(Self.floored(unionRect), edgePadding: insets, animated: false)

                installFog(on: mapView, coordinator: context.coordinator)
            }
        }

        // A trip that never moved — a wait at a barrier, a two-minute test —
        // still has a place, and «where you were» is the one thing the preview
        // can honestly show. Without this the map got a rect of zero size,
        // MapKit zoomed to its limit and drew a blank grey field with a lone
        // dot in it, which reads as a broken map rather than a short trip.
        if coordinates.count < 2, let only = coordinates.first {
            mapView.setVisibleMapRect(
                Self.floored(MKMapRect(origin: MKMapPoint(only), size: MKMapSize(width: 0, height: 0))),
                animated: false
            )
        }

        // Start / end dots
        if let first = coordinates.first {
            let pin = MKPointAnnotation()
            pin.coordinate = first
            pin.title = "start"
            mapView.addAnnotation(pin)
        }
        if coordinates.count > 1, let last = coordinates.last {
            let pin = MKPointAnnotation()
            pin.coordinate = last
            pin.title = "end"
            mapView.addAnnotation(pin)
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.adoptMap(mapView)
        // Одна и та же карта живёт и в слоте героя (пальцев не принимает), и
        // на полном экране (принимает все). Эти четыре свойства ставились
        // один раз при сборке — с общей картой их приходится держать здесь.
        applyInteractivity(to: mapView)
        applyLayoutMargins(to: mapView, coordinator: context.coordinator)
        context.coordinator.onRouteTap = onRouteTap
        context.coordinator.installTapRecognizerIfNeeded(on: mapView, wanted: onRouteTap != nil)
        context.coordinator.syncCheckpoints(checkpointMarkers, style: checkpointMarkerStyle, on: mapView)
        context.coordinator.playbackFollowing = playbackFollow
        context.coordinator.syncCandidates(checkpointCandidates, on: mapView)
        context.coordinator.onPhotoTap = onPhotoTap
        context.coordinator.onCheckpointTap = onCheckpointTap
        context.coordinator.syncFocus(focusCoordinate, on: mapView)
        context.coordinator.syncPhotoPins(photoPins, on: mapView)
        context.coordinator.applyZoom(tick: zoomTick, mapView: mapView)
        context.coordinator.applyFit(tick: fitTick, insets: fitInsets, mapView: mapView)
        context.coordinator.applyCarColor(carColorName, on: mapView)
        context.coordinator.applyPlayback(
            carCoord: playbackCarCoord,
            trailIndex: playbackTrailIndex,
            coords: playbackCoords ?? coordinates,
            mapView: mapView
        )
        context.coordinator.applyCamera(
            follow: playbackFollow,
            car: playbackCarCoord,
            spanMetres: playbackFollowSpan,
            mapView: mapView
        )
    }

    /// Туман «как было на финише этой поездки».
    ///
    /// Слой считается ВНЕ главного актёра и кэшируется на дату
    /// (`TemporalFogCache`), поэтому карта-герой и полноэкранная карта той же
    /// поездки платят за него один раз на двоих. До готовности карта просто
    /// без вуали: показать маршрут на секунду раньше тумана честнее, чем
    /// держать экран пустым.
    ///
    /// Вставляется в САМЫЙ НИЗ `.aboveLabels` — над дорогами и подписями
    /// Apple, но под маршрутом, который уже лежит на этом уровне.
    ///
    /// Срез без даты — это «мир, как он есть сейчас», и он умеет измениться
    /// прямо под открытым экраном: так живёт карточка итогов, которую
    /// показывают в ту же секунду, когда только что законченная поездка ещё
    /// не легла в слой. Поэтому у него, и только у него, карта переспрашивает
    /// слой по `.revealedLayerChanged` — это и есть момент, когда туман
    /// выгорает по сегодняшней дороге.
    private func installFog(on mapView: MKMapView, coordinator: Coordinator) {
        guard showsFog, !coordinator.fogRequested else { return }
        coordinator.fogRequested = true
        coordinator.loadFog(before: fogCutoffDate, on: mapView)
        if fogCutoffDate == nil { coordinator.watchRevealedLayer(on: mapView) }
    }

    /// Пальцы карты. Вынесено: с общей картой (см. `host`) эти свойства
    /// меняются при каждом раскрытии, а не ставятся раз при сборке.
    private func applyInteractivity(to mapView: MKMapView) {
        if mapView.isScrollEnabled != isInteractive { mapView.isScrollEnabled = isInteractive }
        if mapView.isZoomEnabled != isInteractive { mapView.isZoomEnabled = isInteractive }
        if mapView.isRotateEnabled != isInteractive { mapView.isRotateEnabled = isInteractive }
        // Наклон под экранной вуалью запрещён: перспективу аффинной матрицей
        // не выразить, и коридор уехал бы от дороги под ним
        // (`VeilFrame.residual`). Поворот при этом остаётся — он выражается
        // точно.
        let pitch = isInteractive && !showsFog
        if mapView.isPitchEnabled != pitch { mapView.isPitchEnabled = pitch }
    }

    /// Apple requires the Maps attribution to stay visible, and it is laid
    /// out against these margins. Without this the replay's transport row
    /// sits right on top of it.
    private func applyLayoutMargins(to mapView: MKMapView, coordinator: Coordinator) {
        // Исходные поля запоминаются при первой встрече: без `fitInsets`
        // карта их не трогала НИКОГДА, и «поставить ноль» сдвинуло бы
        // логотип Apple у каждой карты-героя. Возврат с полного экрана
        // обязан вернуть именно их, а не ноль.
        if coordinator.defaultLayoutMargins == nil {
            coordinator.defaultLayoutMargins = mapView.layoutMargins
        }
        let wanted: UIEdgeInsets
        if let fitInsets {
            wanted = UIEdgeInsets(
                top: 0, left: fitInsets.left,
                bottom: max(0, fitInsets.bottom - 24), right: fitInsets.right
            )
        } else {
            wanted = coordinator.defaultLayoutMargins ?? mapView.layoutMargins
        }
        guard mapView.layoutMargins != wanted else { return }
        mapView.layoutMargins = wanted
    }

    func makeCoordinator() -> Coordinator {
        // Общая карта — общий координатор: он делегат карты и держит её
        // память (оверлеи, отметки, посадку вуали). Второй координатор на ту
        // же карту означал бы вторую вуаль.
        let make = {
            // `rotatable` решает запас растра вуали, и решается он на всю
            // жизнь карты. У карты с хостом полный экран впереди по
            // определению, поэтому запас берётся сразу поворотный.
            Coordinator(showsFog: showsFog, rotatable: isInteractive || host != nil)
        }
        if let host {
            let coordinator = host.coordinator(orMake: make)
            coordinator.host = host
            return coordinator
        }
        return make()
    }

    /// Экран закрылся — вуаль уходит с ним: два растра и `CADisplayLink` за
    /// кадром не живут.
    ///
    /// У карты с хостом это НЕ конец экрана, а переезд между слотом героя и
    /// полноэкранной раскладкой: снимать там нечего, и снимает по-настоящему
    /// `TripMapHost.tearDown`.
    static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
        guard !coordinator.isHosted else {
            // Одно представление ушло — это либо переезд между слотом героя и
            // полноэкранным слоем, либо уход самого экрана. Различает их
            // СЧЁТЧИК в хосте, а не догадка здесь.
            coordinator.host?.release()
            return
        }
        coordinator.veilSeat?.detach()
    }

    // MARK: - Gap Detection (with parallel speeds array)

    /// Split coordinates + speeds into continuous segments, breaking at gaps > threshold.
    /// Extends GeometryUtils.splitByGaps with parallel speed array support.
    private static func splitIntoSegments(
        _ coords: [CLLocationCoordinate2D],
        speeds: [Double],
        gapThreshold: Double
    ) -> [([CLLocationCoordinate2D], [Double])] {
        guard coords.count >= 2 else { return [(coords, speeds)] }
        let hasSpeeds = speeds.count == coords.count
        var segments: [([CLLocationCoordinate2D], [Double])] = []
        var curCoords: [CLLocationCoordinate2D] = [coords[0]]
        var curSpeeds: [Double] = hasSpeeds ? [speeds[0]] : []
        for i in 1..<coords.count {
            if GeometryUtils.haversineDistance(coords[i - 1], coords[i]) > gapThreshold {
                if curCoords.count >= 2 { segments.append((curCoords, curSpeeds)) }
                curCoords = [coords[i]]
                curSpeeds = hasSpeeds ? [speeds[i]] : []
            } else {
                curCoords.append(coords[i])
                if hasSpeeds { curSpeeds.append(speeds[i]) }
            }
        }
        if curCoords.count >= 2 { segments.append((curCoords, curSpeeds)) }
        return segments
    }

    // MARK: - Speed Zone Grouping

    struct SpeedGroup {
        var coords: [CLLocationCoordinate2D]
        let speed: Double // representative speed for color
    }

    /// Group consecutive points that fall in the same speed color zone into single polylines.
    /// Reduces overlay count from O(points) to O(zone_changes).
    static func groupBySpeedZone(_ route: SimplifiedRoute) -> [SpeedGroup] {
        guard route.coords.count >= 2 else { return [] }
        var groups: [SpeedGroup] = []
        var currentZone = speedZone(route.speeds[0])
        var currentCoords: [CLLocationCoordinate2D] = [route.coords[0]]
        var currentSpeed = route.speeds[0]

        for i in 1..<route.coords.count {
            let zone = speedZone(route.speeds[i])
            if zone == currentZone {
                currentCoords.append(route.coords[i])
            } else {
                // Close current group (overlap last point for continuity)
                currentCoords.append(route.coords[i])
                groups.append(SpeedGroup(coords: currentCoords, speed: currentSpeed))
                // Start new group from this point
                currentZone = zone
                currentCoords = [route.coords[i]]
                currentSpeed = route.speeds[i]
            }
        }
        if currentCoords.count >= 2 {
            groups.append(SpeedGroup(coords: currentCoords, speed: currentSpeed))
        }
        return groups
    }

    /// Map speed to zone index for grouping. Delegates to `SpeedColorScale`
    /// so grouping, polyline colour, and the on-map legend never drift apart.
    private static func speedZone(_ speedMS: Double) -> Int {
        SpeedColorScale.zone(forSpeedMS: speedMS)
    }

    // MARK: - Simplification with speeds

    struct SimplifiedRoute {
        let coords: [CLLocationCoordinate2D]
        let speeds: [Double] // one per coordinate (segment speed = speeds[i] for segment i→i+1)
    }

    /// Simplify coordinates while keeping associated speed values.
    /// Порог упрощения при ОТРИСОВКЕ, в градусах (~2 метра).
    ///
    /// Стояло 0.0001 — семь-одиннадцать метров поперёк линии. То есть карта
    /// сама срезала ровно те углы, ради которых 0.6.5 и стала писать чаще:
    /// заезд во двор со смещением в пять метров схлопывался в прямую уже после
    /// записи, и никакая плотность точек этого бы не спасла.
    ///
    /// Два метра — чуть выше шума GPS: манёвр остаётся, дрожание уходит.
    /// Опускать ниже незачем, там начинается не форма, а шум.
    ///
    /// **Потолка «на длинных треках упрощай грубее» здесь нет намеренно.** Он
    /// был написан из опасения, что подробность дорого обойдётся многочасовой
    /// поездке, — и замер это опроверг: цену диктуют переходы между скоростными
    /// зонами, а не порог. Впятеро более подробная линия стоит процентов на
    /// двадцать дороже (`RouteOverlayCostTests`). Отбирать у долгой поездки её
    /// дворы ради этих двадцати процентов — плохая сделка, а длинная поездка
    /// как раз та, ради которой всё и затевалось.
    static let drawEpsilon: Double = 0.00002

    static func simplifyWithSpeeds(
        _ coords: [CLLocationCoordinate2D],
        speeds: [Double],
        epsilon: Double
    ) -> SimplifiedRoute {
        guard coords.count > 2 else {
            return SimplifiedRoute(coords: coords, speeds: speeds)
        }
        let indices = GeometryUtils.simplifyIndices(coords, startIndex: 0, endIndex: coords.count - 1, epsilon: epsilon)
        let sortedIndices = indices.sorted()
        let newCoords = sortedIndices.map { coords[$0] }
        let newSpeeds = sortedIndices.map { speeds[$0] }
        return SimplifiedRoute(coords: newCoords, speeds: newSpeeds)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        /// Last zoom tick applied, so a re-render for any other reason does not
        /// re-run the zoom.
        private var lastZoomTick: Int = 0

        /// Слой тумана уже заказан. Заказ один на жизнь карты: он перебирает
        /// библиотеку, и повторять его на каждый `updateUIView` (а тот приходит
        /// на каждый кадр реплея) нельзя.
        var fogRequested = false
        private var fogCutoff: Date?
        /// Кто из двух загрузок ложится на карту — см. `FogLoadSequencer`.
        private var fogLoads = FogLoadSequencer()
        private var installedVeil: FogVeilOverlay?
        private var revealObserver: NSObjectProtocol?

        /// Посадка экранной вуали — та же, что у «Атласа» и у экрана записи.
        /// `nil` у чужой поездки и у путешествия: там тумана нет вовсе.
        ///
        /// Место — ПОД контейнером оверлеев: сама поездка нарисована
        /// `MKOverlayRenderer`-ом (отрезки по скорости, обводка, гашение
        /// непройденного на реплее), и вуаль выше неё спрятала бы поездку.
        let veilSeat: VeilSeat?
        /// Карта, на которой мы сидим, — чтобы вернуть ей плиточный оверлей,
        /// когда вуаль уйдёт с экрана.
        private weak var mapRef: MKMapView?
        /// Последний слой, приехавший из `TemporalFogCache`. Держим отдельно от
        /// оверлея: вуаль встаёт в дерево не обязательно раньше, чем слой
        /// досчитается, и опоздавшей посадке его надо чем-то отдать.
        private var loadedLayer: RevealedLayer?

        init(showsFog: Bool, rotatable: Bool) {
            // Повернуть карту можно только пальцами, а пальцы у неё есть
            // только на полном экране: карта-герой поворота не знает, и платить
            // за него вчетверо большим растром ей не за что.
            veilSeat = showsFog
                ? VeilSeat(
                    margin: rotatable ? FogVeilView.rotatingMargin : FogVeilView.defaultMargin,
                    seat: .aboveBaseMap)
                : nil
            super.init()
            veilSeat?.onAttached = { [weak self] in self?.screenVeilTookOver() }
            veilSeat?.onDetached = { [weak self] in self?.screenVeilStoodDown() }
        }

        deinit {
            if let revealObserver { NotificationCenter.default.removeObserver(revealObserver) }
        }

        // MARK: Экранная вуаль

        /// Вуаль встала в дерево: плиточный оверлей с карты снимаем (иначе
        /// туман рисуется дважды, а нижний слой не виден) и отдаём ей слой.
        private func screenVeilTookOver() {
            guard let veil = veilSeat?.veil else { return }
            if let old = installedVeil { mapRef?.removeOverlay(old) }
            if let layer = loadedLayer { veil.setLayer(layer) }
            veilSeat?.startTracking(tail: 1.5)
        }

        /// Вуаль ушла — туман возвращается плиточному рендереру, иначе карта
        /// осталась бы голой.
        private func screenVeilStoodDown() {
            guard let veil = installedVeil, let map = mapRef,
                  !map.overlays.contains(where: { $0 is FogVeilOverlay }) else { return }
            map.insertOverlay(veil, at: 0, level: .aboveLabels)
        }

        /// Карта готова — запоминаем её и сажаем вуаль. Идемпотентно: зовётся и
        /// из `makeUIView`, и из `updateUIView` (тот приходит на каждый кадр
        /// реплея), а контейнеры MapKit появляются в дереве не к первому кадру.
        func adoptMap(_ mapView: MKMapView) {
            mapRef = mapView
            veilSeat?.attach(to: mapView)
        }

        /// Куда ложится готовый слой: в экранную вуаль или плиточным оверлеем.
        ///
        /// Развилка одна на все поводы (первая загрузка, перечитывание по
        /// `.revealedLayerChanged`, опоздавшая посадка вуали) — второй ответ на
        /// этот вопрос означал бы туман в два слоя.
        ///
        /// Плиточный оверлей собирается ВСЕГДА, даже когда рисует вуаль, — он и
        /// есть откат, и `screenVeilStoodDown` кладёт на карту именно его. Без
        /// этого потеря места в дереве (`verifySeating` → `standDown`) или
        /// незнакомая иерархия будущей iOS оставила бы экран поездки с
        /// маршрутом поверх ГОЛОЙ карты Apple — молча, потому что туман просто
        /// не появился бы. Обычный порядок на этом экране — вуаль садится
        /// РАНЬШЕ, чем досчитается срез, поэтому «присвоим потом» значило бы
        /// «никогда».
        func installFogLayer(_ layer: RevealedLayer, on mapView: MKMapView) {
            loadedLayer = layer
            if let old = installedVeil { mapView.removeOverlay(old) }
            let overlay = FogVeilOverlay(layer: layer)
            installedVeil = overlay
            if let seat = veilSeat, seat.isAttached {
                seat.veil.setLayer(layer)
                return
            }
            mapView.insertOverlay(overlay, at: 0, level: .aboveLabels)
        }

        /// Забрать слой и подменить вуаль. Старую снимаем сами: две вуали,
        /// лежащие друг на друге, дают двойную плотность там, где коридор
        /// прочищен только у одной.
        func loadFog(before cutoff: Date?, on mapView: MKMapView, fresh: Bool = false) {
            fogCutoff = cutoff
            let token = fogLoads.begin()
            Task { @MainActor [weak self, weak mapView] in
                let layer = fresh
                    ? await TemporalFogCache.shared.reload(before: cutoff)
                    : await TemporalFogCache.shared.layer(before: cutoff)
                guard let self, let mapView else { return }
                // Обогнавшая старая загрузка сняла бы свежую вуаль и положила
                // дотуристическую — молча и ровно на карточке итогов.
                guard self.fogLoads.isCurrent(token), !layer.isEmpty else { return }
                self.installFogLayer(layer, on: mapView)
            }
        }

        /// Открытое пополнилось — перечитать. Только для среза «сейчас»:
        /// прошлое поездки на её собственную дату не меняется.
        func watchRevealedLayer(on mapView: MKMapView) {
            guard revealObserver == nil else { return }
            revealObserver = NotificationCenter.default.addObserver(
                forName: .revealedLayerChanged, object: nil, queue: .main
            ) { [weak self, weak mapView] _ in
                MainActor.assumeIsolated {
                    guard let self, let mapView else { return }
                    // `fresh`: кэш мог не успеть узнать о том же уведомлении —
                    // порядок наблюдателей у `NotificationCenter` не наш.
                    self.loadFog(before: self.fogCutoff, on: mapView, fresh: true)
                }
            }
        }
        /// Своя ли это поездка — от этого зависит толщина линии и обводка.
        /// Ставится в `makeUIView`, до первой отрисовки.
        var showsFog = false

        /// Картой владеет `TripMapHost`, а не представление.
        ///
        /// Меняет ровно два ответа: `dismantleUIView` перестаёт снимать
        /// вуаль (это переезд, а не уход экрана) и то же делает обработчик
        /// ухода карты из окна. Снимает вуаль в этом режиме только
        /// `TripMapHost.tearDown`.
        var isHosted = false

        /// Кто владеет картой. Нужен одному месту — `dismantleUIView`, куда
        /// приходит только координатор. Слабая: хост держит координатора.
        weak var host: TripMapHost?

        /// Поля карты, какими их поставил MapKit. См. `applyLayoutMargins`.
        var defaultLayoutMargins: UIEdgeInsets?

        /// Маршрут рисуется по-разному на двух картах, и разница не
        /// косметическая: на светлой карте чужой поездки линия в 4 pt — это
        /// сама поездка, а в прочищенном коридоре своей она перекрывает ту
        /// самую живую карту, ради которой коридор и прожигали. Внутри тумана
        /// — 3.2 pt с тёмной обводкой, как у выбранной жилки Атласа.
        func routeRenderer(for polyline: MKPolyline) -> MKPolylineRenderer {
            let renderer: MKPolylineRenderer
            if showsFog {
                let cased = CasedPolylineRenderer(polyline: polyline)
                // Здесь, а не в `draw`: мы на главном потоке и ещё до первой
                // отрисовки — см. `CasedPolylineRenderer.buildCasing`.
                cased.buildCasing()
                renderer = cased
            } else {
                renderer = MKPolylineRenderer(polyline: polyline)
            }
            renderer.lineWidth = showsFog ? RouteVeinRenderer.selectedWidth : 4
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        /// One step of the «+» / «−» buttons: halve or double the visible span.
        func applyZoom(tick: Int, mapView: MKMapView) {
            guard tick != lastZoomTick else { return }
            let zoomingIn = tick > lastZoomTick
            lastZoomTick = tick
            var region = mapView.region
            let factor = zoomingIn ? 0.5 : 2.0
            region.span = MKCoordinateSpan(
                latitudeDelta: min(max(region.span.latitudeDelta * factor, 0.0005), 120),
                longitudeDelta: min(max(region.span.longitudeDelta * factor, 0.0005), 120)
            )
            mapView.setRegion(region, animated: true)
        }

        private var lastFitTick: Int = 0

        /// Вписать весь маршрут в НЫНЕШНИЕ границы карты.
        ///
        /// Заказывается, когда карта уже приехала в новый размер: MapKit
        /// считает подгонку по текущим границам вида, и та же подгонка,
        /// заказанная посреди пружины, вписала бы маршрут в промежуточный
        /// кадр — и на полном экране он остался бы в четверть экрана.
        func applyFit(tick: Int, insets: UIEdgeInsets?, mapView: MKMapView) {
            guard tick != lastFitTick else { return }
            lastFitTick = tick
            guard !overviewRect.isNull else { return }
            let use = insets ?? UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30)
            overviewInsets = use
            mapView.setVisibleMapRect(
                RouteMapView.floored(overviewRect), edgePadding: use, animated: true)
        }

        /// The whole-route rect the map opened on, so «обзор» can return to it.
        var overviewRect: MKMapRect = .null
        var overviewInsets = UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30)
        /// Whether the camera is currently riding with the car.
        private var following = false

        /// Camera mode for the replay: ride with the playback head, or frame
        /// the whole route.
        ///
        /// Entering follow mode animates once, to a street-level box around the
        /// car; from then on the centre is moved without animation, every
        /// frame, which is how a navigation camera behaves. Animating each
        /// frame would queue 60 competing animations a second and the map
        /// would visibly lag behind the car.
        func applyCamera(
            follow: Bool,
            car: CLLocationCoordinate2D?,
            spanMetres: Double,
            mapView: MKMapView
        ) {
            guard follow else {
                guard following else { return }
                following = false
                guard !overviewRect.isNull else { return }
                mapView.setVisibleMapRect(
                    RouteMapView.floored(overviewRect),
                    edgePadding: overviewInsets,
                    animated: true
                )
                return
            }
            guard let car else { return }
            if following {
                // Let the zoom-in that started this mode finish. Without the
                // pause the very next playback frame calls setCenter, which
                // cancels the animation — and the camera arrives by a cut
                // rather than by moving there.
                guard CACurrentMediaTime() >= followAnimationUntil else { return }
                mapView.setCenter(car, animated: false)
            } else {
                following = true
                followAnimationUntil = CACurrentMediaTime() + 0.45
                mapView.setRegion(
                    MKCoordinateRegion(
                        center: car,
                        latitudinalMeters: spanMetres,
                        longitudinalMeters: spanMetres
                    ),
                    animated: true
                )
            }
        }

        private var followAnimationUntil: CFTimeInterval = 0

        /// Отрезки маршрута в порядке следования. Воспроизведение гасит
        /// ими непройденное; добавляются один раз и живут до перестройки
        /// карты — оверлеи при этом НЕ пересоздаются ни разу.
        var speedRun: [SpeedPolyline] = []
        /// Накопленная длина по точкам маршрута воспроизведения, в метрах.
        /// Считается один раз на поездку: пересчитывать её на каждом кадре —
        /// это тысячи гаверсинусов шестьдесят раз в секунду.
        var playbackCum: [Double] = []
        /// Доля, до которой сейчас подсвечено. Меняется редко, поэтому
        /// прозрачность отрезков трогается только когда она реально уехала.
        var litFraction: Double = -1

        weak var playbackCar: PlaybackCarAnnotation?

        /// Снимок на карте: квадратик со скруглением и белой рамкой.
        ///
        /// Рамка обязательна: без неё тёмный кадр сливается с картой, а светлый
        /// — с дорогой, и снимок перестаёт читаться как объект.
        private static func photoPin(_ image: UIImage?) -> UIImage {
            let side: CGFloat = 40
            let size = CGSize(width: side, height: side)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                let outer = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10)
                UIColor.white.setFill()
                outer.fill()

                let inset = CGRect(origin: .zero, size: size).insetBy(dx: 2.5, dy: 2.5)
                let inner = UIBezierPath(roundedRect: inset, cornerRadius: 8)
                if let image {
                    ctx.cgContext.saveGState()
                    inner.addClip()
                    // Заполняем квадрат по короткой стороне, чтобы кадр не тянуло.
                    let scale = max(inset.width / image.size.width, inset.height / image.size.height)
                    let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    image.draw(in: CGRect(
                        x: inset.midX - drawn.width / 2,
                        y: inset.midY - drawn.height / 2,
                        width: drawn.width, height: drawn.height))
                    ctx.cgContext.restoreGState()
                } else {
                    UIColor(white: 0.82, alpha: 1).setFill()
                    inner.fill()
                }
            }
        }

        private static let markerAccent = UIColor(red: 194/255, green: 69/255, blue: 43/255, alpha: 1)
        private static let markerText = UIColor(red: 0.11, green: 0.10, blue: 0.09, alpha: 1)
        private static let markerSecondary = UIColor(red: 0.42, green: 0.40, blue: 0.38, alpha: 1)

        /// Кандидат: мягкое кольцо акцента вокруг, белое кольцо, точка акцента в
        /// центре — точка стоит ровно на линии маршрута. С номером, когда
        /// кандидатов несколько.
        static func candidateImage(number: Int?) -> UIImage {
            let side: CGFloat = 52
            let size = CGSize(width: side, height: side)
            return UIGraphicsImageRenderer(size: size).image { ctx in
                let cg = ctx.cgContext
                let full = CGRect(origin: .zero, size: size)
                markerAccent.withAlphaComponent(0.22).setFill()
                cg.fillEllipse(in: full)
                UIColor.white.setFill()
                cg.fillEllipse(in: full.insetBy(dx: 14, dy: 14))
                markerAccent.setFill()
                cg.fillEllipse(in: full.insetBy(dx: 18, dy: 18))
                if let number {
                    let badge = CGRect(x: side - 22, y: 0, width: 22, height: 22)
                    UIColor.white.setFill()
                    cg.fillEllipse(in: badge)
                    markerAccent.setFill()
                    cg.fillEllipse(in: badge.insetBy(dx: 2, dy: 2))
                    draw("\(number)", font: .systemFont(ofSize: 12, weight: .heavy),
                         color: .white, centeredIn: badge)
                }
            }
        }

        static func checkpointMarkerImage(_ m: CheckpointMarker, style: CheckpointMarkerStyle) -> UIImage {
            switch style {
            case .compact: return compactMarker(m)
            case .labelled: return labelledMarker(m)
            }
        }

        /// Кружок 32 pt: снимок в круге с белой рамкой, без снимка — номер на
        /// акценте. Для маленькой карты, где подпись только мешала бы.
        private static func compactMarker(_ m: CheckpointMarker) -> UIImage {
            let side: CGFloat = 32
            let size = CGSize(width: side, height: side)
            return UIGraphicsImageRenderer(size: size).image { ctx in
                let full = CGRect(origin: .zero, size: size)
                UIColor.white.setFill()
                ctx.cgContext.fillEllipse(in: full)
                let inner = full.insetBy(dx: 2.5, dy: 2.5)
                if let image = m.image {
                    ctx.cgContext.saveGState()
                    UIBezierPath(ovalIn: inner).addClip()
                    drawFilling(image, in: inner)
                    ctx.cgContext.restoreGState()
                } else {
                    markerAccent.setFill()
                    ctx.cgContext.fillEllipse(in: inner)
                    draw("\(m.number)", font: .systemFont(ofSize: 14, weight: .heavy),
                         color: .white, centeredIn: inner)
                }
            }
        }

        /// Карточка с хвостиком: снимок (или номер), имя и «1:30 · 128 км».
        ///
        /// Размеры подобраны под ролик с экрана: имя 13 pt, время 12 pt, всё
        /// на белом с тенью — читается и на светлой карте, и на тёмной, не зумя.
        private static func labelledMarker(_ m: CheckpointMarker) -> UIImage {
            let nameFont = UIFont.systemFont(ofSize: 13, weight: .heavy)
            let readingFont = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            let title = (m.name?.isEmpty == false) ? m.name! : "#\(m.number)"

            let thumb: CGFloat = 44
            let pad: CGFloat = 7
            let gap: CGFloat = 8
            let maxText: CGFloat = 150
            let titleWidth = min(maxText, ceil((title as NSString).size(withAttributes: [.font: nameFont]).width))
            let readingWidth = min(maxText, ceil((m.reading as NSString).size(withAttributes: [.font: readingFont]).width))
            let textWidth = max(titleWidth, readingWidth)

            let cardW = pad + thumb + gap + textWidth + pad + 2
            let cardH = pad + thumb + pad
            let tail: CGFloat = 8
            let shadow: CGFloat = 6
            let size = CGSize(width: cardW + shadow * 2, height: cardH + tail + shadow * 2)

            return UIGraphicsImageRenderer(size: size).image { ctx in
                let cg = ctx.cgContext
                let card = CGRect(x: shadow, y: shadow, width: cardW, height: cardH)

                // Карточка + хвостик одним контуром, чтобы тень легла на оба.
                let path = UIBezierPath(roundedRect: card, cornerRadius: 14)
                let tip = CGPoint(x: card.midX, y: card.maxY + tail)
                path.move(to: CGPoint(x: card.midX - tail, y: card.maxY - 1))
                path.addLine(to: tip)
                path.addLine(to: CGPoint(x: card.midX + tail, y: card.maxY - 1))
                path.close()

                cg.saveGState()
                cg.setShadow(offset: CGSize(width: 0, height: 2), blur: shadow, color: UIColor.black.withAlphaComponent(0.28).cgColor)
                UIColor.white.setFill()
                path.fill()
                cg.restoreGState()

                // Снимок или номер.
                let thumbRect = CGRect(x: card.minX + pad, y: card.minY + pad, width: thumb, height: thumb)
                let thumbPath = UIBezierPath(roundedRect: thumbRect, cornerRadius: 10)
                if let image = m.image {
                    cg.saveGState()
                    thumbPath.addClip()
                    drawFilling(image, in: thumbRect)
                    cg.restoreGState()
                } else {
                    markerAccent.setFill()
                    thumbPath.fill()
                    draw("\(m.number)", font: .systemFont(ofSize: 18, weight: .heavy),
                         color: .white, centeredIn: thumbRect)
                }

                // «+2» на уголке снимка — есть ещё кадры, посмотри.
                if m.image != nil, m.photoCount > 1 {
                    let chipText = "+\(m.photoCount - 1)"
                    let chipFont = UIFont.systemFont(ofSize: 10, weight: .heavy)
                    let w = ceil((chipText as NSString).size(withAttributes: [.font: chipFont]).width) + 8
                    let chip = CGRect(x: thumbRect.maxX - w + 3, y: thumbRect.maxY - 14 + 3, width: w, height: 14)
                    UIColor.white.setFill()
                    UIBezierPath(roundedRect: chip.insetBy(dx: -1.5, dy: -1.5), cornerRadius: 8.5).fill()
                    markerText.setFill()
                    UIBezierPath(roundedRect: chip, cornerRadius: 7).fill()
                    draw(chipText, font: chipFont, color: .white, centeredIn: chip)
                }

                // Имя сверху, время снизу.
                let textX = thumbRect.maxX + gap
                let titleRect = CGRect(x: textX, y: thumbRect.minY + 3, width: textWidth, height: 17)
                let readingRect = CGRect(x: textX, y: thumbRect.maxY - 18, width: textWidth, height: 16)
                let truncating = NSMutableParagraphStyle()
                truncating.lineBreakMode = .byTruncatingTail
                (title as NSString).draw(in: titleRect, withAttributes: [
                    .font: nameFont, .foregroundColor: markerText, .paragraphStyle: truncating])
                (m.reading as NSString).draw(in: readingRect, withAttributes: [
                    .font: readingFont, .foregroundColor: markerSecondary, .paragraphStyle: truncating])
            }
        }

        /// Заполнить прямоугольник снимком по короткой стороне, не растягивая.
        private static func drawFilling(_ image: UIImage, in rect: CGRect) {
            guard image.size.width > 0, image.size.height > 0 else { return }
            let scale = max(rect.width / image.size.width, rect.height / image.size.height)
            let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2,
                                  width: drawn.width, height: drawn.height))
        }

        private static func draw(_ text: String, font: UIFont, color: UIColor, centeredIn rect: CGRect) {
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let bounds = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(
                at: CGPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2),
                withAttributes: attributes)
        }

        /// Цвет машины этой поездки — им красится маркер. `nil` — «без
        /// транспорта», маркер берёт цвет гаража по умолчанию.
        private var carColorName: String?
        private var hasCarColor = false
        /// Курс маркера по земле. Живёт в координаторе, а не в виде: вид
        /// MapKit вправе выбросить и создать заново, и вместе с ним пропал бы
        /// весь набранный поворот.
        private var carCourse: Double = 0
        /// Был ли курс хоть раз достоверным. Пока не был — держать нечего, и
        /// первый же ответ геометрии ставится без доводки.
        private var carHasCourse = false
        private var lastCarTick: CFTimeInterval = 0

        func applyCarColor(_ name: String?, on mapView: MKMapView) {
            guard !hasCarColor || carColorName != name else { return }
            hasCarColor = true
            carColorName = name
            guard let annotation = playbackCar,
                  let view = mapView.view(for: annotation) as? MapCarAnnotationView else { return }
            view.setState(carState)
        }

        /// Состояние маркера реплея.
        ///
        /// Из шести состояний живой записи здесь честны ноль: точность — это
        /// свойство той, прошлой секунды, а не этой; пауза и «нет сигнала»
        /// говорят про запись, которая давно закончилась; пульс сообщал бы,
        /// что сигнал живой, там, где никакого сигнала уже нет. Остаётся цвет
        /// машины — и тень со схлопыванием, которые состояния не спрашивают.
        var carState: MapCarMarker.State {
            MapCarMarker.State(colorName: carColorName)
        }

        /// Доля маршрута, пройденная машиной, от 0 до 1.
        ///
        /// Считается по НАКОПЛЕННОЙ длине, а не по номеру точки: точки лежат
        /// неравномерно, и «сотая из двухсот» на треке с плотным городом и
        /// пустой трассой означает совсем не половину пути.
        func progressFraction(
            car: CLLocationCoordinate2D,
            trailIndex: Int,
            coords: [CLLocationCoordinate2D]
        ) -> Double {
            if playbackCum.count != coords.count {
                var cum: [Double] = [0]
                cum.reserveCapacity(coords.count)
                var total: Double = 0
                for i in 1..<coords.count {
                    total += GeometryUtils.haversineDistance(coords[i - 1], coords[i])
                    cum.append(total)
                }
                playbackCum = cum
            }
            return Self.fraction(cum: playbackCum, coords: coords, car: car, trailIndex: trailIndex)
        }

        /// Само правило — чистой функцией, потому что это правило, а не
        /// отрисовка: ступенька по точке за раз, уход за единицу на последнем
        /// кадре и отрицательный индекс на первом ловятся тестом, а не глазами
        /// на телефоне.
        static func fraction(
            cum: [Double],
            coords: [CLLocationCoordinate2D],
            car: CLLocationCoordinate2D,
            trailIndex: Int
        ) -> Double {
            guard let total = cum.last, total > 0, cum.count == coords.count else { return 0 }
            let i = min(max(trailIndex, 0), coords.count - 1)
            // Плюс кусок до машины: она стоит МЕЖДУ точками, и без этого
            // подсветка дёргалась бы ступеньками по точке за раз.
            let partial = GeometryUtils.haversineDistance(coords[i], car)
            return min(1, max(0, (cum[i] + partial) / total))
        }

        /// Подсветить маршрут до доли `fraction`, приглушив остальное.
        ///
        /// Трогает только те отрезки, у которых прозрачность реально меняется:
        /// за поездку это столько раз, сколько в маршруте отрезков скорости, а
        /// не шестьдесят раз в секунду.
        func relight(to fraction: Double, mapView: MKMapView) {
            guard !speedRun.isEmpty else { return }
            guard abs(fraction - litFraction) > 0.0005 || fraction >= 1 || fraction <= 0 else { return }
            let wasLit = litFraction
            litFraction = fraction
            var touched: [MKOverlayRenderer] = []
            for poly in speedRun {
                let passedNow = poly.endFraction <= fraction
                let passedBefore = wasLit >= 0 && poly.endFraction <= wasLit
                guard passedNow != passedBefore || wasLit < 0 else { continue }
                guard let r = mapView.renderer(for: poly) else { continue }
                r.alpha = passedNow ? 1 : Self.dimmedAhead
                touched.append(r)
            }
            // Возврат яркости после «×» надо ТРЕБОВАТЬ, а не ждать.
            //
            // Смена `alpha` у рендерера помечает его тайлы устаревшими, но
            // перерисовывает их MapKit лениво — когда сам решит. На стоящей
            // карте решал он через две-пять секунд: реплей уже закрыт, а
            // маршрут ещё приглушён впереди машинки, которой нет
            // (находка владельца на устройстве). Голый `setNeedsDisplay()`
            // не помогает — он помечает ВЕСЬ мир и попадает в ту же
            // ленивую очередь; адресный вызов на видимый прямоугольник с
            // нынешним масштабом перерисовывает его в ближайшем кадре.
            //
            // Только на возврате к полной яркости: во время игры доля
            // меняется столько раз, сколько в маршруте отрезков скорости, и
            // требовать перерисовку на каждом было бы дороже самой игры.
            guard fraction >= 1, !touched.isEmpty else { return }
            let rect = mapView.visibleMapRect
            guard rect.size.width > 0, mapView.bounds.width > 0 else { return }
            let zoom = MKZoomScale(Double(mapView.bounds.width) / rect.size.width)
            for renderer in touched { renderer.setNeedsDisplay(rect, zoomScale: zoom) }
        }

        /// Насколько гаснет непройденное.
        ///
        /// Не в ноль и не в серое: маршрут впереди обязан остаться читаемым —
        /// человек смотрит на форму дороги целиком, а не только на то, где
        /// сейчас машина. И цвет скорости там тот же, просто тише: это
        /// содержание экрана, и подменять его нейтральным нельзя.
        static let dimmedAhead: CGFloat = 0.3

        func applyPlayback(
            carCoord: CLLocationCoordinate2D?,
            trailIndex: Int,
            coords: [CLLocationCoordinate2D],
            mapView: MKMapView,
        ) {
            guard coords.count >= 2 else { return }
            // Cleanup branch — controller cleared its state (playback ended
            // or stopped). Drop annotation + both overlays.
            guard let car = carCoord else {
                // Воспроизведение кончилось — маршрут снова весь яркий.
                relight(to: 1, mapView: mapView)
                if let c = playbackCar {
                    mapView.removeAnnotation(c)
                    playbackCar = nil
                }
                carHasCourse = false
                lastCarTick = 0
                return
            }
            // Прогресс показывается ЯРКОСТЬЮ самого маршрута, а не белой
            // линией под ним. Так исчезают обе жалобы разом: белой каймы с
            // жёстким краем больше нет, и — главное — ни один оверлей не
            // добавляется и не удаляется во время воспроизведения. Прежний
            // след пересоздавался на каждой пройденной точке, а хвостик до
            // машины — на КАЖДОМ кадре, шестьдесят раз в секунду; во время
            // щипка карта растрирует оверлеи и тянет растр, и подмена в этот
            // момент рвала картинку.
            let fraction = progressFraction(car: car, trailIndex: trailIndex, coords: coords)
            relight(to: fraction, mapView: mapView)

            // Car position — KVO-observed `@objc dynamic coordinate` on
            // PlaybackCarAnnotation lets MapKit reposition the view
            // without any overlay churn. Frame cadence comes from the
            // controller's CADisplayLink.
            // Курс считается ДО создания вида: иначе на первом кадре маркер
            // успевает показаться смотрящим на север.
            updateCarHeading(at: car, passed: trailIndex, coords: coords, mapView: mapView)
            if let annotation = playbackCar {
                annotation.coordinate = car
            } else {
                let annotation = PlaybackCarAnnotation(coordinate: car)
                mapView.addAnnotation(annotation)
                playbackCar = annotation
            }
        }

        /// Повернуть машину туда, куда она едет.
        ///
        /// Курс берётся ПО ГЕОМЕТРИИ с упреждением, а не из разницы соседних
        /// кадров: полилиния хранит координаты в одинарной точности, и за один
        /// кадр машина сдвигается меньше, чем на квант хранения — знак такой
        /// разницы чистый шум. Само правило — в `CarHeadingPolicy`, здесь
        /// только его применение к текущему кадру.
        private func updateCarHeading(
            at position: CLLocationCoordinate2D,
            passed index: Int,
            coords: [CLLocationCoordinate2D],
            mapView: MKMapView
        ) {
            let now = CACurrentMediaTime()
            // Первый кадр после паузы или подмотки не должен считаться за
            // секунду простоя: доводка углов идёт от реального шага времени.
            let dt = lastCarTick > 0 ? min(now - lastCarTick, 0.5) : 1.0 / 60
            lastCarTick = now

            let target = CarHeadingPolicy.courseAlongRoute(
                from: position, passed: index, in: coords
            )
            if !carHasCourse, let target {
                carCourse = target
                carHasCourse = true
            } else {
                // Reduce Motion: поворот остаётся, доводка уходит — угол
                // встаёт сразу. Правило целиком в `CarHeadingPolicy`.
                carCourse = CarHeadingPolicy.smoothed(
                    current: carCourse, target: target, dt: dt,
                    instant: UIAccessibility.isReduceMotionEnabled
                )
            }

            guard let annotation = playbackCar,
                  let view = mapView.view(for: annotation) as? MapCarAnnotationView else { return }
            view.apply(course: carCourse, cameraHeading: mapView.camera.heading)
        }

        /// Карту повернули пальцами (или камера пошла по курсу) — экранный
        /// угол маркера считается от поворота камеры, и без этого маркер
        /// отвязывается от дороги под собой.
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            veilSeat?.startTracking()
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Камера встала — один ЧЁТКИЙ кадр под новый масштаб.
            veilSeat?.settle(on: mapView)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            // Ловит и жест, и программный полёт камеры (реплей ведёт её сам,
            // без `regionWillChange`): `startTracking` заводит `CADisplayLink`,
            // если его нет, и продлевает хвост, если есть.
            veilSeat?.startTracking()
            guard let annotation = playbackCar,
                  let view = mapView.view(for: annotation) as? MapCarAnnotationView else { return }
            view.applyScreenAngle(cameraHeading: mapView.camera.heading)
            // Масштаб меняется тем же жестом, что и поворот: отсюда маркер
            // узнаёт, не пора ли схлопнуться в точку.
            view.setScale(metersPerPoint: mapView.metersPerScreenPoint)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let veil = overlay as? FogVeilOverlay {
                return FogVeilRenderer(veil: veil)
            }
            if let speedLine = overlay as? SpeedPolyline {
                let renderer = routeRenderer(for: speedLine)
                renderer.strokeColor = Self.color(forSpeedMS: speedLine.speed)
                return renderer
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = routeRenderer(for: polyline)
                renderer.strokeColor = UIColor(red: 252/255, green: 76/255, blue: 2/255, alpha: 0.9) // accent
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        /// Maps speed (m/s) to a stroke colour. Thresholds + colours live in
        /// `SpeedColorScale`, shared with every other renderer of the track:
        ///  0-50 green · 50-90 yellow · 90-110 orange · 110+ red (km/h).
        private static func color(forSpeedMS speed: Double) -> UIColor {
            SpeedColorScale.uiColor(forSpeedMS: speed)
        }

        // MARK: Отметки

        var onRouteTap: ((CLLocationCoordinate2D, Double) -> Void)?
        private var tapRecognizer: UITapGestureRecognizer?
        private var checkpointAnnotations: [CheckpointAnnotation] = []
        private var candidateAnnotations: [CheckpointCandidateAnnotation] = []
        /// Пока камера едет за машиной, подъезжать к кандидату нельзя — два
        /// `setCenter` спорят покадрово, и побеждает реплей.
        var playbackFollowing = false

        func installTapRecognizerIfNeeded(on mapView: MKMapView, wanted: Bool) {
            if wanted, tapRecognizer == nil {
                let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
                recognizer.delegate = self
                mapView.addGestureRecognizer(recognizer)
                tapRecognizer = recognizer
            } else if !wanted, let recognizer = tapRecognizer {
                mapView.removeGestureRecognizer(recognizer)
                tapRecognizer = nil
            }
        }

        /// Тап по булавке или маркеру — это выбор булавки, а не «поставить
        /// отметку под ней»: без этой проверки по фото прилетали оба события.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard recognizer === tapRecognizer, let mapView = recognizer.view else { return true }
            var hit = mapView.hitTest(touch.location(in: mapView), with: nil)
            while let view = hit, view !== mapView {
                if view is MKAnnotationView { return false }
                hit = view.superview
            }
            return true
        }

        /// Не отбирать у карты её собственные жесты.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView, mapView.bounds.width > 0 else { return }
            let point = recognizer.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            let mapPointsPerScreenPoint = mapView.visibleMapRect.size.width / Double(mapView.bounds.width)
            let metersPerPoint = mapPointsPerScreenPoint
                * MKMetersPerMapPointAtLatitude(mapView.centerCoordinate.latitude)
            onRouteTap?(coordinate, metersPerPoint)
        }

        /// Кандидаты пересобираются на каждое касание. Когда они появляются,
        /// карта подъезжает так, чтобы точка оказалась в верхней трети экрана:
        /// внизу встанет карточка с числами, и накрывать ею то, ради чего человек
        /// нажимал, нельзя.
        func syncCandidates(_ candidates: [CheckpointCandidate], on mapView: MKMapView) {
            let have = candidateAnnotations.map(\.candidate)
            guard candidates != have else { return }

            mapView.removeAnnotations(candidateAnnotations)
            candidateAnnotations = candidates.map { CheckpointCandidateAnnotation(candidate: $0) }
            mapView.addAnnotations(candidateAnnotations)

            guard let first = candidates.first else { return }
            reveal(first.coordinate, on: mapView)
        }

        /// Подвозит точку в верхнюю треть экрана — над карточкой внизу.
        /// Уже на виду в нужной зоне — карту не дёргаем.
        private func reveal(_ coordinate: CLLocationCoordinate2D, on mapView: MKMapView) {
            guard !playbackFollowing else { return }
            let target = CGPoint(x: mapView.bounds.midX, y: mapView.bounds.height * 0.36)
            let current = mapView.convert(coordinate, toPointTo: mapView)
            let visible = CGRect(x: 0, y: mapView.bounds.height * 0.12,
                                 width: mapView.bounds.width, height: mapView.bounds.height * 0.45)
            guard !visible.contains(current) else { return }
            let shifted = CGPoint(x: mapView.bounds.midX + (current.x - target.x),
                                  y: mapView.bounds.midY + (current.y - target.y))
            mapView.setCenter(mapView.convert(shifted, toCoordinateFrom: mapView), animated: true)
        }

        var onCheckpointTap: ((UUID) -> Void)?
        private var lastFocus: CLLocationCoordinate2D?

        func syncFocus(_ coordinate: CLLocationCoordinate2D?, on mapView: MKMapView) {
            let same = coordinate.map { c in
                lastFocus.map { $0.latitude == c.latitude && $0.longitude == c.longitude } ?? false
            } ?? (lastFocus == nil)
            guard !same else { return }
            lastFocus = coordinate
            if let coordinate { reveal(coordinate, on: mapView) }
        }

        /// Маркеры живут отдельно от точек старта и финиша: их пересобирают на
        /// каждое изменение списка, а те ставятся один раз при сборке карты.
        /// Сравниваем целиком, включая имя и снимок: имя дозревает из
        /// геокодера позже координаты, миниатюра — позже имени.
        func syncCheckpoints(
            _ markers: [CheckpointMarker],
            style: CheckpointMarkerStyle,
            on mapView: MKMapView
        ) {
            let have = checkpointAnnotations.map(\.marker)
            guard markers != have || checkpointAnnotations.first?.style != style else { return }

            mapView.removeAnnotations(checkpointAnnotations)
            checkpointAnnotations = markers.map { CheckpointAnnotation(marker: $0, style: style) }
            mapView.addAnnotations(checkpointAnnotations)
        }

        var onPhotoTap: ((UUID) -> Void)?
        private var photoAnnotations: [PhotoAnnotation] = []

        func syncPhotoPins(_ pins: [PhotoPin], on mapView: MKMapView) {
            // Сравниваем и по картинкам: миниатюры доезжают позже координат, и
            // без этого на карте навсегда осталась бы серая заглушка.
            let wanted = pins.map { "\($0.id)-\($0.image == nil ? 0 : 1)" }
            let have = photoAnnotations.map { "\($0.photoId)-\($0.image == nil ? 0 : 1)" }
            guard wanted != have else { return }

            mapView.removeAnnotations(photoAnnotations)
            photoAnnotations = pins.map {
                PhotoAnnotation(coordinate: $0.coordinate, photoId: $0.id, image: $0.image,
                                accessibilityLabel: $0.accessibilityLabel)
            }
            mapView.addAnnotations(photoAnnotations)
        }

        /// Новая отметка не «возникает» — она встаёт на место: пружина от
        /// 0.6 до 1, прерываемая (пружина, а не цепочка withAnimation+sleep,
        /// как велит CLAUDE.md). Только для отметок и кандидатов: точки старта
        /// и финиша ставятся один раз при сборке, им анимация ни к чему.
        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            guard !UIAccessibility.isReduceMotionEnabled else { return }
            for view in views where view.annotation is CheckpointAnnotation || view.annotation is CheckpointCandidateAnnotation {
                view.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
                view.alpha = 0
                UIView.animate(springDuration: 0.45, bounce: 0.3) {
                    view.transform = .identity
                    view.alpha = 1
                }
            }
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let photo = view.annotation as? PhotoAnnotation {
                mapView.deselectAnnotation(view.annotation, animated: false)
                onPhotoTap?(photo.photoId)
            } else if let checkpoint = view.annotation as? CheckpointAnnotation {
                // Своё выделение не держим: карточку рисует экран, а MapKit
                // при выделении поднимает вид и меняет коллизии соседей.
                mapView.deselectAnnotation(view.annotation, animated: false)
                onCheckpointTap?(checkpoint.marker.id)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let candidate = annotation as? CheckpointCandidateAnnotation {
                let id = "CheckpointCandidate"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.canShowCallout = false
                view.image = Self.candidateImage(number: candidate.candidate.number)
                view.isAccessibilityElement = true
                view.accessibilityLabel = candidate.candidate.accessibilityLabel
                view.accessibilityTraits = .button
                view.centerOffset = .zero
                // Кандидат обязан быть виден всегда и над всем остальным.
                view.displayPriority = .required
                view.collisionMode = .circle
                view.zPriority = MKAnnotationViewZPriority(rawValue: 990)
                // Дыхание — «это ещё не поставлено, это предложение». Без него
                // кандидат читался бы как готовая отметка. Повторяющаяся
                // анимация — ровно то, что Reduce Motion просит убрать: тогда
                // кольцо стоит неподвижно, и этого достаточно.
                view.layer.removeAnimation(forKey: "pulse")
                if !UIAccessibility.isReduceMotionEnabled {
                    let pulse = CABasicAnimation(keyPath: "transform.scale")
                    pulse.fromValue = 0.92
                    pulse.toValue = 1.08
                    pulse.duration = 0.9
                    pulse.autoreverses = true
                    pulse.repeatCount = .infinity
                    pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    view.layer.add(pulse, forKey: "pulse")
                }
                return view
            }
            if let photo = annotation as? PhotoAnnotation {
                let id = "TripPhoto"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.canShowCallout = false
                view.image = Self.photoPin(photo.image)
                view.centerOffset = .zero
                // Снимки уступают место отметкам: при наложении MapKit прячет
                // их, а не карточку с «1 ч 19 мин».
                view.isAccessibilityElement = true
                view.accessibilityLabel = photo.voiceLabel
                view.accessibilityIdentifier = "map_photo_pin"
                view.accessibilityTraits = .image
                view.displayPriority = .defaultLow
                view.collisionMode = .circle
                view.zPriority = MKAnnotationViewZPriority(rawValue: 850)
                return view
            }
            if let checkpoint = annotation as? CheckpointAnnotation {
                let id = "Checkpoint"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.canShowCallout = false
                let image = Self.checkpointMarkerImage(checkpoint.marker, style: checkpoint.style)
                view.image = image
                view.isAccessibilityElement = true
                view.accessibilityLabel = [checkpoint.marker.name ?? "#\(checkpoint.marker.number)",
                                           checkpoint.marker.reading].joined(separator: ", ")
                // Подписанный маркер стоит НАД точкой хвостиком вниз; кружок —
                // центром на точке.
                view.centerOffset = checkpoint.style == .labelled
                    ? CGPoint(x: 0, y: -image.size.height / 2)
                    : .zero
                // Отметки важнее снимков, но не обязаны быть видны все разом:
                // две карточки на одном пятачке — MapKit оставит одну.
                view.displayPriority = .defaultHigh
                view.collisionMode = checkpoint.style == .labelled ? .rectangle : .circle
                view.zPriority = MKAnnotationViewZPriority(rawValue: 950)
                view.selectedZPriority = .max
                return view
            }
            // Машинка реплея. Картинка собрана и закэширована по цвету, а
            // поворот — это трансформация её слоя, не новая растеризация.
            if annotation is PlaybackCarAnnotation {
                let id = MapCarAnnotationView.reuseIdentifier
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MapCarAnnotationView
                    ?? MapCarAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.setState(carState)
                view.setScale(metersPerPoint: mapView.metersPerScreenPoint)
                view.apply(course: carCourse, cameraHeading: mapView.camera.heading)
                view.displayPriority = .required
                view.collisionMode = .none
                view.zPriority = .max
                return view
            }
            guard let point = annotation as? MKPointAnnotation else { return nil }

            let isStart = point.title == "start"
            let id = isStart ? "StartDot" : "EndDot"

            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.canShowCallout = false

            let size: CGFloat = 10
            let color: UIColor = isStart
                ? UIColor(red: 48/255, green: 209/255, blue: 88/255, alpha: 1)
                : UIColor(red: 255/255, green: 69/255, blue: 58/255, alpha: 1)

            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            view.image = renderer.image { ctx in
                color.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: CGSize(width: size, height: size)))
            }
            view.centerOffset = .zero
            return view
        }
    }
}
