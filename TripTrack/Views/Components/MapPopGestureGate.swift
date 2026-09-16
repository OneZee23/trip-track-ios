import SwiftUI
import UIKit

/// Пока карта поездки раскрыта на весь экран — свайп от левого края не
/// уводит с экрана.
///
/// До 0.7.0 полный экран был `fullScreenCover`, и системная презентация
/// перехватывала межстраничный жест сама. Слоем внутри пушнутого экрана он
/// перестал быть перехваченным: палец от левого края выкидывал из поездки
/// прямо из «полного экрана» — из состояния, которое выглядит отдельным
/// экраном и своего «назад» не имеет.
///
/// Гасится ровно тот распознаватель, до которого уже дотягивается
/// `NavBarKiller` (`interactivePopGestureRecognizer`), и тем же путём — через
/// `navigationController` вью-контроллера в дереве. Возвращает его обратно
/// `dismantleUIViewController`: слой живёт ровно столько, сколько раскрытие,
/// поэтому «включить назад» не может быть забыто ни на одном пути выхода —
/// ни на закрытии, ни на уходе экрана, ни на разрыве хоста.
struct MapPopGestureGate: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.setPopEnabled(true)
    }

    final class Controller: UIViewController {
        override func loadView() {
            let view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            self.view = view
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // Не в `viewWillAppear`: `NavBarKiller` в своём включает жест
            // обратно, и порядок двух `viewWillAppear` в одном дереве нам не
            // принадлежит. `viewDidAppear` приходит после обоих.
            setPopEnabled(false)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            setPopEnabled(true)
        }

        func setPopEnabled(_ enabled: Bool) {
            navigationController?.interactivePopGestureRecognizer?.isEnabled = enabled
        }
    }
}
