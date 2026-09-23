import XCTest
import MapKit
import CoreLocation
@testable import TripTrack

/// Экранная вуаль на ТРЁХ картах: одна и та же вью, разные места в дереве и
/// разные запасы растра.
///
/// Проверяется здесь именно то, что нельзя увидеть глазами: место в иерархии
/// (сел не туда — либо поездки не видно под туманом, либо тумана нет вовсе),
/// запас (не тот — полный кадр на каждый поворот руля) и главное обещание
/// прорези у машины — «растёт, ничего не заказывая».
@MainActor
final class VeilSeatTests: XCTestCase {

    // MARK: Дерево карты — подставное

    /// Дерево `MKMapView`, снятое спайком на устройстве: контейнер оверлеев
    /// (в нём рисует `MKOverlayRenderer`) и контейнер аннотаций — соседи, а
    /// хостинг самой карты Apple лежит левее обоих.
    private func mapTree() -> (root: UIView, content: UIView,
                               base: UIView, overlays: UIView, annotations: UIView) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let content = UIView(frame: root.bounds)
        root.addSubview(content)
        let base = UIView(frame: content.bounds)
        content.addSubview(base)
        let overlays = ScrollContainerStub(frame: content.bounds)
        content.addSubview(overlays)
        let annotations = AnnotationContainerStub(frame: content.bounds)
        content.addSubview(annotations)
        return (root, content, base, overlays, annotations)
    }

    // MARK: Место в дереве

    /// «Атлас»: вуаль ВЫШЕ оверлеев (свои он с карты снимает и рисует в растр),
    /// но ниже пинов и подписей регионов.
    func testAtlasSeatsTheVeilAboveOverlaysAndBelowAnnotations() {
        let tree = mapTree()
        let veil = FogVeilView()

        XCTAssertTrue(veil.attach(inside: tree.root, seat: .belowAnnotations))
        let order = tree.content.subviews
        XCTAssertLessThan(order.firstIndex(of: veil)!, order.firstIndex(of: tree.annotations)!,
                          "вуаль обязана лежать ПОД аннотациями")
        XCTAssertGreaterThan(order.firstIndex(of: veil)!, order.firstIndex(of: tree.overlays)!,
                             "на «Атласе» оверлеи сняты — вуаль лежит выше их контейнера")
    }

    /// Экран поездки и экран записи: вуаль НИЖЕ контейнера оверлеев.
    ///
    /// Иначе она накроет собой то, ради чего экран открыт: линию поездки с
    /// отрезками по скорости, обводку, гашение непройденного на реплее и
    /// светящуюся голову на записи. Увести это в растр нельзя — растр стоит
    /// десятки миллисекунд, а реплей идёт кадрами.
    func testTripAndRecordingSeatTheVeilUnderTheOverlayContainer() {
        let tree = mapTree()
        let veil = FogVeilView(margin: FogVeilView.rotatingMargin)

        XCTAssertTrue(veil.attach(inside: tree.root, seat: .aboveBaseMap))
        let order = tree.content.subviews
        XCTAssertLessThan(order.firstIndex(of: veil)!, order.firstIndex(of: tree.overlays)!,
                          "маршрут рисуется оверлеем и обязан остаться ВЫШЕ тумана")
        XCTAssertGreaterThan(order.firstIndex(of: veil)!, order.firstIndex(of: tree.base)!,
                             "но саму карту Apple с её подписями туман обязан накрыть")
    }

    /// Контейнера оверлеев в дереве нет — вуаль НЕ садится вовсе.
    ///
    /// Это откат, а не «сядем куда придётся»: вуаль, севшая выше оверлеев,
    /// нарисовала бы точно такой же туман и молча спрятала бы под ним поездку.
    func testTripFallsBackWhenTheOverlayContainerIsMissing() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let content = UIView(frame: root.bounds)
        root.addSubview(content)
        content.addSubview(AnnotationContainerStub(frame: content.bounds))

        let veil = FogVeilView()
        XCTAssertFalse(veil.attach(inside: root, seat: .aboveBaseMap))
        XCTAssertNil(veil.superview, "не встроились — значит на экране нас нет вовсе")
    }

    /// Вуаль вылетела из дерева — садится обратно НА СВОЁ место, а не на
    /// «Атласово».
    func testReseatingKeepsTheSameSeat() {
        let tree = mapTree()
        let veil = FogVeilView()
        XCTAssertTrue(veil.attach(inside: tree.root, seat: .aboveBaseMap))

        veil.removeFromSuperview()
        veil.verifySeating()

        let order = tree.content.subviews
        XCTAssertLessThan(order.firstIndex(of: veil)!, order.firstIndex(of: tree.overlays)!,
                          "после возврата вуаль снова под оверлеями")
    }

    // MARK: Metal-слой в дереве

    /// Своё место Metal-слоя — тот же родитель, что у вуали, и НИЖЕ её.
    ///
    /// Проверяет это чистая функция, а не живое дерево: вопрос у неё
    /// арифметический, а цена ошибки несимметрична. Всплыл поверх вуали —
    /// жилка сети и выбранный маршрут ушли под мглу; вылетел из дерева —
    /// «Атлас» остался БЕЗ тумана вовсе, потому что растра у вуали нет
    /// (`vectorOnly`), а плиточные оверлеи сняты.
    func testFogMetalSeatIsJudgedByParentAndOrder() {
        let parent = UIView()
        let metal = UIView()
        let veil = UIView()
        parent.addSubview(metal)
        parent.addSubview(veil)
        XCTAssertFalse(FogMetalSeat.needsReseating(metal: metal, veil: veil),
                       "в том же родителе и ниже вуали — это и есть своё место")

        parent.bringSubviewToFront(metal)
        XCTAssertTrue(FogMetalSeat.needsReseating(metal: metal, veil: veil),
                      "поверх вуали мгла накрыла бы жилку и выбранный маршрут")

        metal.removeFromSuperview()
        XCTAssertTrue(FogMetalSeat.needsReseating(metal: metal, veil: veil),
                      "вылетел из дерева — тумана на «Атласе» не осталось вовсе")

        XCTAssertFalse(FogMetalSeat.needsReseating(metal: metal, veil: UIView()),
                       "вуаль сама вне дерева — садиться не подо что, спросят снова")
        XCTAssertFalse(FogMetalSeat.needsReseating(metal: nil, veil: veil),
                       "Metal недоступен — пересаживать нечего")
    }

    /// Живое дерево: MapKit пересобрал сабвью и Metal-слой вылетел — вернуть
    /// его обязан ближайший проход разметки.
    ///
    /// Разметка, а не `onLostFromHierarchy`: `FogVeilView.verifySeating`
    /// возвращает СЕБЯ и, вернувшись удачно, молчит, — то есть о пересборке
    /// дерева Metal-слою не сказал бы никто, и «Атлас» показывал бы голую
    /// карту Apple до ухода с экрана и возврата.
    func testALayoutPassPutsTheMetalVeilBackUnderTheRasterOne() throws {
        let host = MapHostController()
        let metal = try XCTUnwrap(host.metalVeil, "Metal недоступен")
        host.loadViewIfNeeded()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        host.view.layoutIfNeeded()
        host.viewDidAppear(false)
        try XCTSkipUnless(host.screenVeilAttached,
                          "дерево MKMapView на этом SDK незнакомое — сажать некуда")
        let parent = try XCTUnwrap(host.screenVeil.superview)

        // Первая посадка тоже за разметкой: `seatFogMetal` висит на
        // `onVeilAttached`, а его ставит представление SwiftUI — здесь его
        // нет, и слой обязан сесть всё равно.
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try assertMetalSitsUnderTheVeil(metal, veil: host.screenVeil, parent: parent)

        metal.removeFromSuperview()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try assertMetalSitsUnderTheVeil(metal, veil: host.screenVeil, parent: parent)
    }

    /// Порядок без принудительных развёрток: упавший `!` уронил бы ВЕСЬ
    /// прогон, а не один тест (CLAUDE.md «Ловушки»).
    private func assertMetalSitsUnderTheVeil(
        _ metal: UIView, veil: UIView, parent: UIView
    ) throws {
        XCTAssertTrue(metal.superview === parent, "Metal-слой садится в родителя вуали")
        let mine = try XCTUnwrap(parent.subviews.firstIndex(of: metal),
                                 "Metal-слоя нет в дереве — «Атлас» без тумана вовсе")
        let theirs = try XCTUnwrap(parent.subviews.firstIndex(of: veil))
        XCTAssertLessThan(mine, theirs, "и ложится ПОД вуаль: сверху жилка и маршрут")
    }

    // MARK: Кто какую вуаль заказывает

    /// Три карты — три заказа, и все три отличаются по существу.
    func testEachMapAsksForItsOwnSeatAndMargin() {
        let atlas = MapHostController().veilSeat
        XCTAssertEqual(atlas.placement, .belowAnnotations)
        XCTAssertEqual(atlas.veil.margin, FogVeilView.atlasMargin, accuracy: 0.0001,
                       "у «Атласа» свой запас: его щипают шире всех и не вращают")

        let recording = MapViewRepresentable(
            userTrackingMode: .constant(.none), zoomDelta: .constant(0)
        ).makeCoordinator().veilSeat
        XCTAssertEqual(recording.placement, .aboveBaseMap)
        XCTAssertEqual(recording.veil.margin, FogVeilView.rotatingMargin, accuracy: 0.0001,
                       "карту записи вращает режим «по курсу» — запас обязан это переживать")

        let fullscreenTrip = RouteMapView(coordinates: [], isInteractive: true, showsFog: true)
            .makeCoordinator().veilSeat
        XCTAssertEqual(fullscreenTrip?.placement, .aboveBaseMap)
        XCTAssertEqual(fullscreenTrip?.veil.margin ?? 0, FogVeilView.rotatingMargin,
                       accuracy: 0.0001, "полноэкранную карту поездки поворачивают пальцами")

        let hero = RouteMapView(coordinates: [], isInteractive: false, showsFog: true)
            .makeCoordinator().veilSeat
        XCTAssertEqual(hero?.veil.margin ?? 0, FogVeilView.defaultMargin, accuracy: 0.0001,
                       "карта-герой поворота не знает — платить за него вчетверо не за что")
    }

    /// Чужая поездка и путешествие (`showsFog == false`): вуали нет вовсе.
    /// Не «есть, но пустая» — её не создают, и восьми мегабайт растра там
    /// не появляется ни на секунду.
    func testForeignTripCreatesNoVeilAtAll() {
        let coordinator = RouteMapView(coordinates: [], showsFog: false).makeCoordinator()
        XCTAssertNil(coordinator.veilSeat)
        XCTAssertNil(coordinator.fogMetal,
                     "и Metal-слоя тоже: второй MTKView за чужой поездкой не живёт")
    }

    /// Все три карты просят СВОЙ Metal-слой, и все три переводят растровую
    /// вуаль в вектор.
    ///
    /// Вторая половина не менее важна первой: не сними мы растр, туман
    /// рисовался бы дважды — раз на GPU и раз восьмимегабайтной картинкой, —
    /// и человек видел бы двойную плотность там, где коридор прочищен только
    /// у одного из двух.
    func testEachMapAsksForItsOwnMetalSeatAndTurnsTheRasterIntoVector() throws {
        let atlas = MapHostController()
        try XCTSkipIf(atlas.metalVeil == nil, "Metal недоступен")
        XCTAssertTrue(atlas.screenVeil.vectorOnly)

        let trip = RouteMapView(coordinates: [], isInteractive: true, showsFog: true)
            .makeCoordinator()
        XCTAssertNotNil(trip.fogMetal?.veil, "карта поездки рисует «мир на ту дату» металом")
        XCTAssertEqual(trip.veilSeat?.veil.vectorOnly, true)

        let recording = MapViewRepresentable(
            userTrackingMode: .constant(.none), zoomDelta: .constant(0)
        ).makeCoordinator()
        XCTAssertNotNil(recording.fogMetal.veil)
        XCTAssertTrue(recording.veilSeat.veil.vectorOnly)
    }

    /// Metal-слой садится ПОД растровую вуаль — то есть на экране поездки и
    /// записи ниже контейнера оверлеев вместе с ней.
    ///
    /// Место здесь решает, видно ли саму поездку: маршрут рисует
    /// `MKOverlayRenderer` — отрезки по скорости, обводка, гашение
    /// непройденного на реплее, светящаяся голова на записи, — и мгла выше
    /// него спрятала бы под собой то, ради чего экран открыт.
    func testTripAndRecordingSeatTheMetalVeilUnderTheirRasterOne() throws {
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let coordinator = RouteMapView(coordinates: [], showsFog: true).makeCoordinator()
        let metal = try XCTUnwrap(coordinator.fogMetal?.veil, "Metal недоступен")
        coordinator.adoptMap(map)
        try XCTSkipUnless(coordinator.veilSeat?.isAttached == true,
                          "MapKit не собрал дерево у карты без окна — проверять нечего")
        let veil = try XCTUnwrap(coordinator.veilSeat?.veil)
        let parent = try XCTUnwrap(veil.superview)
        try assertMetalSitsUnderTheVeil(metal, veil: veil, parent: parent)

        let container = try XCTUnwrap(FogVeilView.overlayContainer(among: parent.subviews),
                                      "у карты поездки вуаль сидит под контейнером оверлеев")
        let mine = try XCTUnwrap(parent.subviews.firstIndex(of: metal))
        let theirs = try XCTUnwrap(parent.subviews.firstIndex(of: container))
        XCTAssertLessThan(mine, theirs,
                          "маршрут рисуется оверлеем и обязан остаться ВЫШЕ мглы")

        // MapKit пересобрал сабвью: вернуть слой обязана ближайшая посадка
        // карты, а её зовёт каждый `updateUIView` (то есть каждый кадр реплея).
        metal.removeFromSuperview()
        coordinator.adoptMap(map)
        try assertMetalSitsUnderTheVeil(metal, veil: veil, parent: parent)
    }

    /// Контейнера оверлеев в дереве нет — не садится НИКТО, ни растр, ни
    /// метал, и туман рисует плиточный рендерер, как до 0.7.0.
    ///
    /// Это откат, а не «сядем куда придётся»: Metal-слой, севший выше
    /// оверлеев, нарисовал бы точно такой же туман и молча спрятал бы под ним
    /// поездку — заметить подмену было бы нечем.
    func testMetalStaysOutOfTheTreeWhenTheOverlayContainerIsMissing() throws {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let content = UIView(frame: root.bounds)
        root.addSubview(content)
        content.addSubview(AnnotationContainerStub(frame: content.bounds))

        let seat = VeilSeat(margin: FogVeilView.rotatingMargin, seat: .aboveBaseMap)
        XCTAssertFalse(seat.veil.attach(inside: root, seat: .aboveBaseMap))

        let metal = FogMetalSeat()
        let veil = try XCTUnwrap(metal.veil, "Metal недоступен")
        metal.follow(seat, on: MKMapView())
        XCTAssertNil(veil.superview, "вуаль не села — Metal-слою садиться не подо что")
        XCTAssertFalse(metal.isSeated)
    }

    // MARK: Временной слой доезжает до вуали

    /// Срез «как было на финише ЭТОЙ поездки» кладётся либо в вуаль, либо
    /// плиточным оверлеем — но НИКОГДА в оба сразу.
    func testTemporalLayerGoesToTheVeilOrToTheOverlayButNeverToBoth() throws {
        let layer = revealedLayer()
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))

        // Вуаль не села (незнакомая иерархия) — работает откат.
        let fallback = RouteMapView(coordinates: [], showsFog: true).makeCoordinator()
        fallback.installFogLayer(layer, on: map)
        XCTAssertEqual(map.overlays.compactMap { $0 as? FogVeilOverlay }.count, 1,
                       "без вуали туман обязан остаться плиточным оверлеем")
        XCTAssertFalse(fallback.veilSeat?.veil.hasInstalledLayer ?? true)

        // Вуаль села — оверлея не появляется вовсе.
        let seated = RouteMapView(coordinates: [], showsFog: true).makeCoordinator()
        let live = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        seated.adoptMap(live)
        try XCTSkipUnless(seated.veilSeat?.isAttached == true,
                          "MapKit не собрал дерево у карты без окна — проверять нечего")
        seated.installFogLayer(layer, on: live)
        XCTAssertTrue(live.overlays.compactMap { $0 as? FogVeilOverlay }.isEmpty,
                      "туман на вуали и оверлеем сразу — это двойная плотность")
        XCTAssertTrue(seated.veilSeat?.veil.hasInstalledLayer ?? false)
    }

    /// Срез на дату доезжает до Metal-слоя — до ТОГО САМОГО, который лежит
    /// под вуалью на этом экране.
    ///
    /// Проводка, а не картинка: `TemporalFogCache` считает слой «как мир
    /// выглядел до этой поездки» и отдаёт его `installFogLayer` — дальше
    /// вопрос ровно один, дошёл ли он до GPU или остался у растровой вуали,
    /// которая на этом экране мглы больше не рисует. Не дошёл бы — экран
    /// поездки показывал бы маршрут поверх ГОЛОЙ карты Apple.
    func testTheTemporalSliceReachesTheMetalVeil() throws {
        let layer = revealedLayer()
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let coordinator = RouteMapView(coordinates: [], showsFog: true).makeCoordinator()
        let metal = try XCTUnwrap(coordinator.fogMetal?.veil, "Metal недоступен")
        coordinator.adoptMap(map)
        try XCTSkipUnless(coordinator.veilSeat?.isAttached == true,
                          "MapKit не собрал дерево у карты без окна — проверять нечего")

        coordinator.installFogLayer(layer, on: map)
        XCTAssertEqual(metal.installedSignature, FogMesh.signature(of: layer),
                       "на GPU обязан уехать ИМЕННО этот срез, а не какой-нибудь")
        XCTAssertTrue(map.overlays.compactMap { $0 as? FogVeilOverlay }.isEmpty,
                      "и плиточным оверлеем он при этом не ложится — это двойная плотность")
    }

    /// Вуаль потеряла место в дереве — плиточный туман обязан ВЕРНУТЬСЯ на
    /// карту, и с тем же слоем.
    ///
    /// Без этого экран поездки остаётся с маршрутом поверх ГОЛОЙ карты Apple:
    /// вуали нет, оверлея нет, и заметить это нечем. Обычный порядок здесь —
    /// вуаль садится РАНЬШЕ, чем досчитается срез, поэтому оверлей обязан
    /// собираться и в той ветке, где рисует вуаль.
    func testLostSeatOnTheTripMapBringsTheTiledFogBack() throws {
        let layer = revealedLayer()
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let coordinator = RouteMapView(coordinates: [], showsFog: true).makeCoordinator()
        coordinator.adoptMap(map)
        try XCTSkipUnless(coordinator.veilSeat?.isAttached == true,
                          "MapKit не собрал дерево у карты без окна — проверять нечего")

        coordinator.installFogLayer(layer, on: map)
        XCTAssertTrue(map.overlays.compactMap { $0 as? FogVeilOverlay }.isEmpty,
                      "пока вуаль на месте, оверлея на карте быть не должно")

        // Место потеряно по-настоящему: контейнера, под которым вуаль сидела,
        // в дереве больше нет — вернуться ей некуда, и `verifySeating` уходит
        // в `onLostFromHierarchy` → `standDown`.
        let container = try XCTUnwrap(FogVeilView.annotationContainer(in: map))
        container.removeFromSuperview()
        coordinator.veilSeat?.veil.superview?.subviews
            .filter { FogVeilView.overlayContainer(among: [$0]) != nil }
            .forEach { $0.removeFromSuperview() }
        coordinator.veilSeat?.veil.verifySeating()
        XCTAssertEqual(coordinator.veilSeat?.isAttached, false, "вуаль обязана сдаться")

        let restored = map.overlays.compactMap { $0 as? FogVeilOverlay }
        XCTAssertEqual(restored.count, 1, "туман обязан вернуться плиточным оверлеем")
        XCTAssertTrue(
            restored.first?.layer.polylines(for: .fine).first
                === layer.polylines(for: .fine).first,
            "и с тем же слоем, а не с пустым")
    }

    /// Карта записи переиздаёт оверлеи до шестидесяти раз в секунду
    /// (светящаяся голова), а плиточного тумана на ней нет вовсе — сравнивать
    /// диффу не с чем. Слой обязан доходить до вуали РОВНО ОДИН раз на оверлей.
    func testRecordingHandsTheSameLayerToTheVeilOnlyOnce() {
        let coordinator = MapViewRepresentable(
            userTrackingMode: .constant(.none), zoomDelta: .constant(0)
        ).makeCoordinator()
        let fog = FogVeilOverlay(layer: revealedLayer())

        for _ in 0..<60 { coordinator.handOverFog(fog) }
        XCTAssertEqual(coordinator.veilSeat.veil.layerHandoffs, 1,
                       "слой ушёл в вуаль \(coordinator.veilSeat.veil.layerHandoffs) раз")
        XCTAssertEqual(coordinator.veilSeat.veil.renderOrders, 0,
                       "и ни одного кадра тумана это заказать не могло")

        // Новый слой (финиш поездки, пул) — новый оверлей и новая передача.
        coordinator.handOverFog(FogVeilOverlay(layer: revealedLayer()))
        XCTAssertEqual(coordinator.veilSeat.veil.layerHandoffs, 2)
    }

    /// Карта стоит, а вуаль из дерева выбило. `sync` этого не ловит —
    /// `CADisplayLink` в покое погашен, — поэтому ловят два других пути: выход
    /// из окна и следующая посадка (`updateUIView`, появление экрана).
    func testStaticMapStillNoticesALostSeat() {
        let tree = mapTree()
        let window = UIWindow(frame: tree.root.bounds)
        window.addSubview(tree.root)
        let veil = FogVeilView()
        XCTAssertTrue(veil.attach(inside: tree.root, seat: .aboveBaseMap))
        XCTAssertNotNil(veil.window, "вуаль обязана оказаться в окне")

        // Выбило из дерева: карта при этом не двигалась ни разу.
        veil.removeFromSuperview()
        XCTAssertTrue(tree.content.subviews.contains(veil),
                      "выход из окна обязан вернуть вуаль на место")

        // Второй путь — перестановка внутри того же родителя: окно не
        // меняется, значит ловит её только ближайшая посадка, а её зовёт
        // каждый `updateUIView`.
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let seat = VeilSeat(margin: FogVeilView.defaultMargin, seat: .aboveBaseMap)
        seat.attach(to: map)
        guard seat.isAttached, let parent = seat.veil.superview,
              let container = FogVeilView.overlayContainer(among: parent.subviews)
        else { return }

        parent.bringSubviewToFront(seat.veil)
        XCTAssertGreaterThan(parent.subviews.firstIndex(of: seat.veil)!,
                             parent.subviews.firstIndex(of: container)!,
                             "подстроили промах: вуаль поверх оверлеев")

        seat.attach(to: map)
        XCTAssertLessThan(parent.subviews.firstIndex(of: seat.veil)!,
                          parent.subviews.firstIndex(of: container)!,
                          "посадка обязана вернуть вуаль под оверлеи")
    }

    // MARK: Прорезь у машины

    /// Главное обещание прорези: она растёт шестьдесят раз в секунду и НЕ
    /// заказывает при этом ни одного кадра тумана.
    ///
    /// Заказала бы — и запись встала бы: полный кадр растра стоит десятки
    /// миллисекунд, а кадров в секунду шестьдесят.
    func testLiveRevealNeverOrdersARaster() {
        let tree = mapTree()
        let map = MKMapView(frame: tree.root.bounds)
        map.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 45.03, longitude: 38.99),
            latitudinalMeters: 1_000, longitudinalMeters: 1_000), animated: false)

        let veil = FogVeilView(margin: FogVeilView.rotatingMargin)
        XCTAssertTrue(veil.attach(inside: tree.root, map: map, seat: .aboveBaseMap))
        veil.setLayer(revealedLayer())

        // Индекс путей собирается вне главного потока — ждём его, иначе
        // заказывать было бы нечего и тест ничего не проверял бы.
        let ready = expectation(description: "индекс путей собран")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { ready.fulfill() }
        wait(for: [ready], timeout: 3)
        veil.maybeRender(map: map, settled: true)
        let ordered = veil.renderOrders
        XCTAssertGreaterThan(ordered, 0, "без единого заказанного кадра проверять нечего")

        // Секунда анимации прорези — БЕЗ единого возврата в главный цикл,
        // чтобы отложенных заказов сюда не попало.
        let car = CLLocationCoordinate2D(latitude: 45.031, longitude: 38.991)
        for frame in 1...60 {
            veil.setLiveReveal(coordinate: car, progress: Double(frame) / 60)
        }
        XCTAssertEqual(veil.renderOrders, ordered,
                       "прорезь заказала \(veil.renderOrders - ordered) кадров тумана")
        XCTAssertTrue(veil.hasLiveReveal)

        // Финиш: коридор прожжён по-настоящему, маска снимается.
        veil.setLiveReveal(coordinate: nil, progress: 0)
        XCTAssertFalse(veil.hasLiveReveal)
        XCTAssertEqual(veil.renderOrders, ordered)
    }

    /// Непрозрачное вокруг прорези — точное дополнение её коробки до экрана.
    /// Дыра там, где её быть не должно, — это дыра в тумане, и видно её только
    /// глазами на движущейся машине.
    func testRevealMaskCoversEverythingButTheHole() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let cases: [(String, CGRect)] = [
            ("прорезь в середине", CGRect(x: 150, y: 400, width: 90, height: 90)),
            ("прорезь у края", CGRect(x: -30, y: 700, width: 120, height: 120)),
            ("прорезь за экраном", CGRect(x: 600, y: 900, width: 60, height: 60)),
        ]
        for (name, hole) in cases {
            let bars = VeilRevealMask.barsAround(bounds: bounds, hole: hole)
            var holes = 0
            for x in stride(from: 0.5, to: bounds.width, by: 3.0) {
                for y in stride(from: 0.5, to: bounds.height, by: 3.0) {
                    let point = CGPoint(x: x, y: y)
                    if hole.contains(point) { continue }
                    if bars.contains(where: { $0.contains(point) }) { continue }
                    holes += 1
                }
            }
            XCTAssertEqual(holes, 0, "\(name): \(holes) точек тумана прозрачны")
            for bar in bars where !bar.isEmpty {
                XCTAssertFalse(bar.intersects(hole.insetBy(dx: 0.5, dy: 0.5)),
                               "\(name): полоса залезла в прорезь")
            }
        }
    }

    // MARK: Отставание привязки

    /// Едет ли туман с картой пиксель в пиксель, когда камера ЛЕТИТ сама.
    ///
    /// Вопрос не теоретический: привязка живёт в `CADisplayLink`, а MapKit
    /// двигает свой контент своим расписанием, и кадр разницы читается как
    /// «пьяная» анимация зума — туман догоняет карту. Числа печатаются:
    /// закрывать вопрос словами здесь нечем.
    func testVeilKeepsUpWithAnAnimatedCameraFlight() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let map = VeilHostMapView(frame: window.bounds)
        window.addSubview(map)
        window.makeKeyAndVisible()
        map.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 45.03, longitude: 38.99),
            latitudinalMeters: 4_000, longitudinalMeters: 4_000), animated: false)

        let veil = FogVeilView(margin: FogVeilView.atlasMargin)
        guard veil.attach(inside: map, map: map, seat: .belowAnnotations) else {
            throw XCTSkip("дерево MKMapView на этом SDK незнакомое — мерить нечего")
        }
        veil.setLayer(revealedLayer())
        let ready = expectation(description: "индекс и первый растр")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { ready.fulfill() }
        wait(for: [ready], timeout: 5)
        veil.maybeRender(map: map, settled: true)
        let drawn = expectation(description: "растр лёг на экран")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { drawn.fulfill() }
        wait(for: [drawn], timeout: 5)

        // Полёт камеры: MapKit анимирует его сам, без единого колбэка о начале
        // жеста — именно тот случай, ради которого вуаль и держит свой
        // `CADisplayLink`.
        // Опора берётся ДО полёта: в headless-прогоне MapKit вправе применить
        // «анимированный» регион мгновенно (так и вышло на iPhone 16 в полном
        // наборе), и опора после вызова читала бы ноль движения у камеры,
        // которая уже приехала.
        var samples: [CGFloat] = []
        var cameraMoved = 0.0
        var previous = map.visibleMapRect
        veil.startTracking(tail: 2.5)
        map.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 45.06, longitude: 39.05),
            latitudinalMeters: 30_000, longitudinalMeters: 30_000), animated: true)

        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(1.0 / 60))
            let now = map.visibleMapRect
            cameraMoved += abs(now.midX - previous.midX) + abs(now.width - previous.width)
            previous = now
            if let lag = veil.syncLag(map: map) { samples.append(lag) }
        }
        XCTAssertGreaterThan(cameraMoved, 0,
                             "камера обязана двигаться — иначе мерить нечего")
        veil.detach()
        window.isHidden = true

        guard !samples.isEmpty else {
            throw XCTSkip("слой ни разу не показался — presentation() пуст, мерить нечего")
        }
        let worst = samples.max() ?? 0
        let mean = samples.reduce(0, +) / CGFloat(samples.count)
        print(String(format: "[veil] отставание привязки: замеров %d, среднее %.3f pt, "
                     + "максимум %.3f pt, камера прошла %.0f точек карты",
                     samples.count, mean, worst, cameraMoved))
        XCTAssertLessThan(mean, 1.0,
                          "в среднем туман отстаёт от карты на \(mean) pt — это видно глазами")
    }

    // MARK: Поворот карты

    /// Режим «по курсу» крутит карту сам. Поворот аффинная матрица выражает
    /// ТОЧНО — невязка ноль на любом курсе; наклон не выражает никак, и на
    /// этом стоит запрет `isPitchEnabled`.
    func testHeadingLeavesNoResidualWhilePitchDoes() {
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let centre = CLLocationCoordinate2D(latitude: 45.03, longitude: 38.99)

        for heading in [0.0, 17.0, 45.0, 90.0, 137.0, 270.0] {
            map.camera = MKMapCamera(lookingAtCenter: centre, fromDistance: 2_000,
                                     pitch: 0, heading: heading)
            guard let residual = residualOfRasterFrame(on: map) else {
                return XCTFail("матрица из трёх точек обязана собраться на курсе \(heading)")
            }
            XCTAssertLessThan(residual, 0.5,
                              "на курсе \(heading) коридор уехал от дороги на \(residual) pt")
        }

        map.camera = MKMapCamera(lookingAtCenter: centre, fromDistance: 2_000,
                                 pitch: 55, heading: 30)
        if let tilted = residualOfRasterFrame(on: map) {
            XCTAssertGreaterThan(tilted, 1,
                                 "при наклоне невязка обязана вырасти — иначе сторожа нет")
        }
    }

    /// Невязка четвёртого угла растра, посчитанная самой картой: три угла
    /// задают матрицу, четвёртый её проверяет.
    private func residualOfRasterFrame(on map: MKMapView) -> CGFloat? {
        let rect = FogVeilView.renderRect(visible: map.visibleMapRect,
                                          margin: FogVeilView.rotatingMargin)
        let size = CGSize(width: 800, height: 1_400)
        guard let frame = VeilFrame(
            p00: map.convert(MKMapPoint(x: rect.minX, y: rect.minY).coordinate, toPointTo: map),
            p10: map.convert(MKMapPoint(x: rect.maxX, y: rect.minY).coordinate, toPointTo: map),
            p01: map.convert(MKMapPoint(x: rect.minX, y: rect.maxY).coordinate, toPointTo: map),
            size: size
        ) else { return nil }
        return frame.residual(
            measured: map.convert(MKMapPoint(x: rect.maxX, y: rect.maxY).coordinate,
                                  toPointTo: map),
            atX: 1, y: 1)
    }

    // MARK: Фикстура открытого мира

    private func revealedLayer() -> RevealedLayer {
        var claimed: [String: Set<RevealGrid.Cell>] = [:]
        var runs: [[CLLocationCoordinate2D]] = []
        let coords = (0..<200).map { i -> CLLocationCoordinate2D in
            let t = Double(i) / 199
            return CLLocationCoordinate2D(latitude: 45.02 + 0.02 * t, longitude: 38.98 + 0.03 * t)
        }
        for (key, patch) in RevealBuilder.patches(for: coords, claimed: { claimed[$0] ?? [] }) {
            claimed[key, default: []].formUnion(patch.cells)
            runs.append(contentsOf: patch.runs)
        }
        return RevealedLayer.build(
            runs: runs, cellCount: claimed.values.reduce(0) { $0 + $1.count }, atlas: nil)
    }
}

/// Подставной контейнер оверлеев: настоящий (`MKScrollContainerView`)
/// приватный, а поиск идёт по подстроке имени класса — ровно это и
/// проверяется.
final class ScrollContainerStub: UIView {}
