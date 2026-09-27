import XCTest
import MapKit
@testable import TripTrack

/// «Вид карты» обязан доезжать до карты БЕЗ участия `updateUIViewController`.
///
/// Владелец на устройстве 27 сентября: «переключение вида карты не работает
/// никак». Три присланных кадра — «Туман», «Ночь», «Клетки» — совпали
/// побайтово во всей полосе карты (у пары «Ночь»/«Клетки» максимум дельты
/// РОВНО НОЛЬ), а посчитанная по пикселям мгла на всех трёх оказалась ночной:
/// доля карты под мглой 0.26 при затемнении листа 0.83 даёт альфу 0.70 и цвет
/// (39, 43, 55) — это `Palette.night.top`. То есть на экране стоял СТАРТОВЫЙ
/// стиль, а не выбранный.
///
/// Причина та же, что у камеры и периода 26 сентября (см. `bindViewModel`):
/// SwiftUI на «Атласе» зовёт `updateUIViewController` только на старте, а
/// стиль ехал исключительно оттуда. Тест бьёт ровно в это место — трогает
/// одну вью-модель и ничего больше, как палец в листе.
///
/// Спрашивается ГРАНИЦА (`MapHostController.appliedAppearance`), а не
/// глобальная `FogVeilPainter.palette`: ту переставляет любой живой хозяин
/// карты на своём проходе разметки, и в полном прогоне соседние тесты роняли
/// проверку, которая по существу верна. Что делает сам `applyPalette`,
/// сторожат его собственные тесты; здесь вопрос один — доехал ли выбор.
@MainActor
final class AtlasAppearanceWiringTests: XCTestCase {

    private var stored: AtlasMapAppearance!

    override func setUp() {
        super.setUp()
        stored = AtlasMapAppearance.load()
    }

    override func tearDown() {
        stored.save()
        super.tearDown()
    }

    /// Подписка читает значение на следующем витке главного актёра.
    private func settle() async {
        try? await Task.sleep(nanoseconds: 60_000_000)
    }

    private func wired(
        from style: AtlasMapAppearance.Style
    ) async -> (MyMapViewModel, MapHostController, MyMapRepresentable.Coordinator) {
        let vm = MyMapViewModel()
        let host = MapHostController()
        host.loadViewIfNeeded()
        let coordinator = MyMapRepresentable.Coordinator()
        coordinator.host = host
        coordinator.bindViewModel(map: host.map, viewModel: vm)
        vm.setAppearance(AtlasMapAppearance(style: style))
        await settle()
        host.setAppearance(vm.appearance)
        XCTAssertEqual(host.appliedAppearance.style, style, "стартовый стиль не встал")
        return (vm, host, coordinator)
    }

    func testPickingNightOnAStandingMapReachesTheMap() async {
        let (vm, host, coordinator) = await wired(from: .fog)
        _ = coordinator

        vm.setAppearance(AtlasMapAppearance(style: .night))
        await settle()

        XCTAssertEqual(host.appliedAppearance.style, .night,
                       "выбрана «Ночь», а карта осталась на прежнем стиле")
    }

    func testPickingFogReachesTheMap() async {
        let (vm, host, coordinator) = await wired(from: .night)
        _ = coordinator

        vm.setAppearance(AtlasMapAppearance(style: .fog))
        await settle()

        XCTAssertEqual(host.appliedAppearance.style, .fog,
                       "выбран «Туман», а карта осталась на прежнем стиле")
    }

    /// «Клетки» палитру не меняют вовсе — они делят её с «Туманом», и
    /// проверить их можно только тем, доехал ли САМ выбор.
    func testPickingCellsReachesTheMap() async {
        let (vm, host, coordinator) = await wired(from: .fog)
        _ = coordinator

        vm.setAppearance(AtlasMapAppearance(style: .cells))
        await settle()

        XCTAssertEqual(host.appliedAppearance.style, .cells,
                       "выбраны «Клетки», а карта осталась на прежнем стиле")
    }

    /// Тумблер «Фото из поездок» ехал тем же мёртвым каналом.
    func testTurningTripPhotosOffReachesTheMap() async {
        let (vm, host, coordinator) = await wired(from: .fog)
        _ = coordinator
        XCTAssertTrue(host.appliedAppearance.showsPhotos, "фото и так были выключены")

        var next = vm.appearance
        next.showsPhotos = false
        vm.setAppearance(next)
        await settle()

        XCTAssertFalse(host.appliedAppearance.showsPhotos,
                       "фото выключены в листе, а карта об этом не узнала")
    }
}
