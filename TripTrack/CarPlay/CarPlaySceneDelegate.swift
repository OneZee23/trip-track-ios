import CarPlay
import UIKit

/// Сцена CarPlay.
///
/// Отдельная сцена от окна телефона, и это не наша прихоть: так устроен
/// CarPlay. Приложение при этом ОДНО — процесс, запись, база и `TripManager`
/// общие, а экран автомобиля лишь ещё одна поверхность к той же поездке
/// (как Live Activity и часы).
///
/// Здесь только жизненный цикл. Всё, что рисуется, живёт в
/// `CarPlayController`, а что именно показать — в чистой `CarPlayScreen`.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var controller: CarPlayController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        carPlayLog.notice("scene connected")
        MainActor.assumeIsolated {
            let controller = CarPlayController(interface: interfaceController)
            self.controller = controller
            controller.start()
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        carPlayLog.notice("scene disconnected")
        MainActor.assumeIsolated {
            controller?.stop()
            controller = nil
        }
    }
}
