import XCTest
@testable import TripTrack

/// Подъём пилюли таб-бара над индикатором «домой» (0.6.8): зазор до
/// индикатора равен боковому полю; на телефонах с кнопкой — канонные 14 pt.
final class CustomTabBarLiftTests: XCTestCase {

    func testHomeIndicatorPhoneGetsSideMarginGap() {
        let lift = CustomTabBar.bottomLift(bottomInset: 34)
        XCTAssertEqual(lift, 24)
        XCTAssertEqual(lift - CustomTabBar.homeIndicatorTop, CustomTabBar.sideMargin)
    }

    func testHomeButtonPhoneKeepsCanon() {
        XCTAssertEqual(CustomTabBar.bottomLift(bottomInset: 0), 14)
    }

    /// Клиренс считается от ФАКТИЧЕСКОГО инсета, а не от пола: с индикатором
    /// 74 + 24 + 8, без него 74 + 14 + 8.
    func testClearanceFollowsInset() {
        XCTAssertEqual(CustomTabBar.clearance(bottomInset: 34), 106)
        XCTAssertEqual(CustomTabBar.clearance(bottomInset: 0), 96)
    }

    /// Внутри стека отсчёт от границы безопасной зоны: 106 − 34 = 72 с
    /// индикатором, 96 − 0 = 96 без него.
    func testClearanceAboveSafeAreaSubtractsTheInset() {
        XCTAssertEqual(CustomTabBar.clearanceAboveSafeArea(bottomInset: 34), 72)
        XCTAssertEqual(CustomTabBar.clearanceAboveSafeArea(bottomInset: 0), 96)
    }

    /// Свёрнутый лист «Атласа» (0.7.0): карточка, клиренс под баром и зазор.
    /// Это же число уезжает в `additionalSafeAreaInsets.bottom` карты — под
    /// непрозрачным туманом логотип Apple и ссылка «Legal» иначе остаются под
    /// листом навсегда, а прятать «Legal» нельзя.
    func testAtlasCollapsedSheetLeavesRoomForTheLegalLink() {
        // Высота карточки — из её же константы, а не числом: она выросла с 64
        // до 86, когда число стало героем («дизайн этой плашки не нравится» —
        // владелец, 23 сен), и ЛЮБАЯ её правка обязана доехать до инсета
        // карты. Переписанное здесь число это правило и проверяет.
        XCTAssertEqual(MyMapSheet.collapsedHeight(bottomInset: 34),
                       MyMapSheet.collapsedCardHeight + 106 + 6)
        XCTAssertEqual(MyMapSheet.collapsedHeight(bottomInset: 0),
                       MyMapSheet.collapsedCardHeight + 96 + 6)
        XCTAssertGreaterThan(
            MyMapSheet.collapsedHeight(bottomInset: 34), 34,
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
        let atlas = MyMapSheet.collapsedHeight(bottomInset: safeArea)
        XCTAssertEqual(
            MapBottomInset.overlayHeight(panelTop: window - atlas, windowHeight: window), atlas)

        // Панель ниже низа окна (первый кадр, окна ещё нет) не имеет права
        // дать отрицательный инсет.
        XCTAssertEqual(MapBottomInset.overlayHeight(panelTop: window + 10, windowHeight: window), 0)
        XCTAssertEqual(MapBottomInset.additional(overlayHeight: 10, safeAreaBottom: 34), 0)
    }
}
