import XCTest
@testable import TripTrack

/// Геометрия бара 0.8.1 — одна на все вкладки (до 0.8.1 «Атлас» нёс свою,
/// а четыре остальные вкладки стеклянную пилюлю 0.6.0 в 74 pt).
final class CustomTabBarLiftTests: XCTestCase {

    /// Зазор до физического низа задан макетом и НЕ зависит от индикатора
    /// «домой»: 22 + 68 капсулы + 12 подъёма диска записи + 8 воздуха.
    /// Прежняя формула считала подъём от инсета и давала 106/96 — под
    /// приподнятый диск этого не хватало.
    func testClearanceIsTheDesignGeometry() {
        XCTAssertEqual(CustomTabBar.clearance, 110)
        XCTAssertEqual(
            CustomTabBar.clearance,
            CustomTabBar.bottomGap + CustomTabBar.pillHeight + CustomTabBar.recordRise + 8)
    }

    /// Внутри стека отсчёт от границы безопасной зоны: 110 − 34 с
    /// индикатором, все 110 без него.
    func testClearanceAboveSafeAreaSubtractsTheInset() {
        XCTAssertEqual(CustomTabBar.clearanceAboveSafeArea(bottomInset: 34), 76)
        XCTAssertEqual(CustomTabBar.clearanceAboveSafeArea(bottomInset: 0), 110)
    }

    /// Инсет больше клиренса не должен давать отрицательный отступ.
    func testClearanceAboveSafeAreaNeverGoesNegative() {
        XCTAssertEqual(CustomTabBar.clearanceAboveSafeArea(bottomInset: 200), 0)
    }

    /// Свёрнутый лист «Атласа»: карточка, клиренс под баром и зазор.
    /// Это же число уезжает в `additionalSafeAreaInsets.bottom` карты — под
    /// непрозрачным туманом логотип Apple и ссылка «Legal» иначе остаются под
    /// листом навсегда, а прятать «Legal» нельзя.
    func testAtlasCollapsedSheetLeavesRoomForTheLegalLink() {
        XCTAssertGreaterThanOrEqual(
            MyMapSheet.collapsedHeight - MyMapSheet.collapsedCardHeight,
            CustomTabBar.clearance,
            "под содержимым должен помещаться приподнятый центр таб-бара")
        XCTAssertGreaterThan(
            MyMapSheet.collapsedHeight, 34,
            "инсет обязан быть больше безопасной зоны, иначе поднимать нечего")
    }

    /// Панель сообщает карте расстояние до ФИЗИЧЕСКОГО низа окна, а не свою
    /// высоту.
    ///
    /// Сводка чужой карты и карты машины лежит в `VStack`, который безопасную
    /// зону уважает: её низ стоит на 34 pt выше физического низа экрана. Пока
    /// она отдавала одну свою высоту, карта считала `extra = высота − 34` и
    /// поднимала «Legal» ровно на эти 34 pt меньше нужного — то есть прятала
    /// его под сводку. У листа «Атласа» ошибки не было: его высота и так
    /// считается от низа окна.
    func testBottomOverlayIsMeasuredToThePhysicalBottomOfTheWindow() {
        let window: CGFloat = 874
        let safeArea: CGFloat = 34
        let summary: CGFloat = 120

        // Сводка в уважающем безопасную зону `VStack`: её верх — на
        // 874 − 34 − 120.
        let reported = MapBottomInset.overlayHeight(
            panelTop: window - safeArea - summary, windowHeight: window)
        XCTAssertEqual(reported, summary + safeArea, "панель отдала свою высоту вместо расстояния")
        XCTAssertEqual(
            MapBottomInset.additional(overlayHeight: reported, safeAreaBottom: safeArea),
            summary,
            "логотип и «Legal» поднялись не на всю сводку")

        // Лист «Атласа» стоит от физического низа — контракт тот же, а число
        // уже верное и без правки.
        let atlas = MyMapSheet.collapsedHeight
        XCTAssertEqual(
            MapBottomInset.overlayHeight(panelTop: window - atlas, windowHeight: window), atlas)

        // Панель ниже низа окна (первый кадр, окна ещё нет) не имеет права
        // дать отрицательный инсет.
        XCTAssertEqual(MapBottomInset.overlayHeight(panelTop: window + 10, windowHeight: window), 0)
        XCTAssertEqual(MapBottomInset.additional(overlayHeight: 10, safeAreaBottom: 34), 0)
    }
}
