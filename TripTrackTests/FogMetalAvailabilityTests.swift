import XCTest
import CoreLocation
import MapKit
@testable import TripTrack

/// Выключатель Metal-тумана и режим «только вектор» у растровой вуали.
///
/// `isEnabled == true` — продакшен 0.8.0; тест на само значение стоит
/// нарочно: смена флага — решение владельца, а не побочный эффект задачи, и
/// она обязана ронять тест, который потом удаляют вместе с решением.
final class FogMetalAvailabilityTests: XCTestCase {

    override func tearDown() {
        FogMetalAvailability.isEnabledOverride = nil
        // Замер полного кадра — процессный `static`, и оставленный после себя
        // он врёт соседям: по нему `FogVeilView.bandCount` решает, резать ли
        // растр на полосы.
        FogVeilView.forgetFullFrameCost()
        super.tearDown()
    }

    func testShippedBuildDrawsFogWithMetal() {
        XCTAssertTrue(FogMetalAvailability.isEnabled)
        XCTAssertTrue(FogMetalAvailability.isActive,
                      "без переопределения «активно» это и есть прод-значение")
    }

    func testOverrideTurnsTheFlagOff() {
        FogMetalAvailability.isEnabledOverride = false
        XCTAssertFalse(FogMetalAvailability.isActive)
        // И обратно: шов не однонаправленный, иначе тест, которому Metal
        // нужен, не смог бы его вернуть.
        FogMetalAvailability.isEnabledOverride = true
        XCTAssertTrue(FogMetalAvailability.isActive)
    }

    // MARK: «Только вектор»

    /// Вуаль в режиме «только вектор» не рисует НИ ОДНОГО растра: мглу рисует
    /// `FogMetalVeil`, и платить за картинку, которую никто не увидит,
    /// незачем.
    ///
    /// Счётчик заказов (`renderOrders`) здесь не сторож: гейт спрашивается
    /// РАНЬШЕ развилки `vectorOnly`, и спрашивается не зря — тем же заказом
    /// едет жилка сети, которая на «Атласе» и остаётся вуали. Заказ, стало
    /// быть, есть у обеих.
    ///
    /// Поэтому проверок две, и обе обязательны: ни одна полоса не легла на
    /// экран (её держит `expected == 0` у растра) И кисть не рисовала ничего
    /// вовсе (её держит развилка в `render`). Порознь каждая половина
    /// проходит на сломанной второй: невыставленная полоса всё равно стоила
    /// бы полного кадра CoreGraphics на каждое движение камеры.
    ///
    /// Индекс путей при этом строится по-прежнему, и это НЕ недосмотр:
    /// бакеты `MapPathIndex` — единственный источник жилки
    /// (`FogVeilVein.strokes` принимает `MapPathChunks`), а жилка на
    /// «Атласе» остаётся вуали. Утверждать здесь «индекс не строится»
    /// значило бы сторожить картинку, отличную от эталона 0.8.0.
    @MainActor
    func testVectorOnlyVeilOrdersNoRaster() {
        let veil = orderARaster(vectorOnly: true)
        XCTAssertGreaterThan(veil.veinStrokeCount, 0,
                             "жилка обязана лечь: без неё заказ не дошёл и проверять нечего")
        XCTAssertEqual(bandLayerCount(veil), 0, "а полос растра не легло на экран ни одной")
        XCTAssertNil(FogVeilView.fullFrameCost, "и кисть CoreGraphics не бралась за кадр")
    }

    /// Обратная половина, без которой первая проходила бы и на вуали,
    /// сломанной насмерть: та же дорога со снятым флагом растр РИСУЕТ.
    @MainActor
    func testTheSameVeilWithoutTheFlagStillRendersARaster() {
        let veil = orderARaster(vectorOnly: false)
        XCTAssertGreaterThan(bandLayerCount(veil), 0,
                             "в откате (Metal недоступен) туман по-прежнему растровый")
        XCTAssertNotNil(FogVeilView.fullFrameCost, "и кисть за кадр бралась")
    }

    /// Окно под подписью Apple на «Атласе» вырезает себе Metal-слой — у
    /// растровой вуали маски не остаётся вовсе.
    ///
    /// Маска у неё одна на весь слой, а на слое в режиме «только вектор»
    /// лежат жилка сети и выбранный маршрут: приглушить их наполовину в углу
    /// с логотипом значит выцветить сеть там, где мгла и без того приглушена.
    @MainActor
    func testVectorOnlyVeilLeavesTheAttributionWindowToMetal() {
        let box = CGRect(x: 12, y: 800, width: 120, height: 26)

        let atlas = FogVeilView(margin: FogVeilView.atlasMargin)
        atlas.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        atlas.vectorOnly = true
        atlas.setAttributionCarve(box)
        XCTAssertNil(atlas.layer.mask, "на «Атласе» окно вырезает Metal-слой, и только он")

        // Две другие карты и откат живут по правилу 0.7.0 целиком.
        let trip = FogVeilView(margin: FogVeilView.rotatingMargin)
        trip.frame = atlas.frame
        trip.setAttributionCarve(box)
        XCTAssertNotNil(trip.layer.mask,
                        "у растровой вуали мглу под подписью приглушает её собственная маска")
    }

    // MARK: Дорога до растра

    /// Доводит вуаль до того места, где растр либо рисуется, либо нет: дерево
    /// карты, слой открытого, собранный индекс путей и один заказ на стоящей
    /// камере.
    @MainActor
    private func orderARaster(vectorOnly: Bool) -> FogVeilView {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let content = UIView(frame: root.bounds)
        root.addSubview(content)
        content.addSubview(ScrollContainerStub(frame: content.bounds))
        content.addSubview(AnnotationContainerStub(frame: content.bounds))

        let map = MKMapView(frame: root.bounds)
        map.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 45.03, longitude: 38.99),
            latitudinalMeters: 1_000, longitudinalMeters: 1_000), animated: false)

        let veil = FogVeilView(margin: FogVeilView.atlasMargin)
        veil.vectorOnly = vectorOnly
        XCTAssertTrue(veil.attach(inside: root, map: map, seat: .belowAnnotations))
        // Забывается ДО первого возможного кадра: замер ставится один раз за
        // процесс, и сбрасывать его после чужого растра было бы поздно.
        FogVeilView.forgetFullFrameCost()
        veil.setLayer(revealedLayer())

        // Индекс путей собирается вне главного потока, а кисть рисует на
        // фоновой очереди: без обоих ожиданий тест проверял бы пустоту.
        settle(0.6)
        veil.maybeRender(map: map, settled: true)
        XCTAssertGreaterThan(veil.renderOrders, 0, "заказ обязан пройти гейт")
        settle(0.8)
        return veil
    }

    /// Сколько слоёв с КАРТИНКОЙ лежит в дереве вуали — то есть сколько полос
    /// растра доехало до экрана. Жилка рисуется `CAShapeLayer`-ами и сюда не
    /// попадает, летербокс — цветом фона.
    @MainActor
    private func bandLayerCount(_ veil: FogVeilView) -> Int {
        func count(_ layer: CALayer) -> Int {
            (layer.contents == nil ? 0 : 1)
                + (layer.sublayers ?? []).reduce(0) { $0 + count($1) }
        }
        return count(veil.layer)
    }

    private func settle(_ seconds: TimeInterval) {
        let done = expectation(description: "фоновая работа")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 5)
    }

    /// Открытый мир из одного прогона — тот же, которым `VeilSeatTests`
    /// доводит вуаль до настоящего заказа кадра.
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
