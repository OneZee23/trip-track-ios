import SwiftUI
import UIKit
import OSLog

private let navLog = Logger(subsystem: "com.triptrack", category: "nav")

/// Forces the underlying `UINavigationController` bar to be visually
/// nothing — transparent background, clear tint (back-button invisible),
/// clear title — AND cancels its safe-area contribution via negative
/// `additionalSafeAreaInsets`. This survives UIKit's push/pop animations
/// where `isHidden` / `alpha` get toggled through the presentation layer
/// (beyond what KVO on the model can intercept): even if the bar paints
/// for a frame, there's simply no visible content in it.
///
/// Use via `.background(NavBarKiller())`. Safe only in stacks where every
/// pushed view wants the bar gone. `CustomNavBar` wires this in.
struct NavBarKiller: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ vc: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func loadView() {
            let v = UIView()
            v.backgroundColor = .clear
            v.isUserInteractionEnabled = false
            view = v
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            blankTheBar(phase: "didMove")
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            blankTheBar(phase: "willAppear")
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            blankTheBar(phase: "didAppear")
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            blankTheBar(phase: "willDisappear")
        }

        override func viewWillLayoutSubviews() {
            super.viewWillLayoutSubviews()
            blankTheBar(phase: "willLayout")
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            blankTheBar(phase: "didLayout")
        }

        /// Make the nav bar completely content-free and transparent, then
        /// subtract its height from the controller's safe area so the
        /// on-screen layout is identical regardless of UIKit toggling
        /// `isHidden` / `alpha` mid-animation.
        private func blankTheBar(phase: String) {
            guard let nav = navigationController else { return }
            let bar = nav.navigationBar

            // Transparent appearance — background, shadow, everything.
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = .clear
            appearance.backgroundEffect = nil
            appearance.shadowColor = .clear
            appearance.shadowImage = UIImage()
            // Title + any large title invisible — mapped color is clear,
            // so even if SwiftUI pushes a title via `.navigationTitle` it
            // renders nothing.
            let clearText: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.clear]
            appearance.titleTextAttributes = clearText
            appearance.largeTitleTextAttributes = clearText
            // Clear back button text + chevron; they draw with `tintColor`.
            let backItem = UIBarButtonItemAppearance(style: .plain)
            backItem.normal.titleTextAttributes = clearText
            backItem.highlighted.titleTextAttributes = clearText
            appearance.backButtonAppearance = backItem

            bar.standardAppearance = appearance
            bar.scrollEdgeAppearance = appearance
            bar.compactAppearance = appearance
            if #available(iOS 15.0, *) {
                bar.compactScrollEdgeAppearance = appearance
            }
            bar.tintColor = .clear
            bar.isTranslucent = true

            // Keep the best-effort hide calls too — they work when UIKit
            // isn't actively animating and save layout cost.
            nav.setNavigationBarHidden(true, animated: false)
            bar.isHidden = true
            bar.alpha = 0

            // Subtract the bar's height from safe area so the flash window
            // doesn't push content down by 44pt.
            let barHeight = bar.frame.height
            nav.additionalSafeAreaInsets = UIEdgeInsets(
                top: -barHeight, left: 0, bottom: 0, right: 0,
            )

            navLog.debug(
                "killer[\(ObjectIdentifier(self).hashValue, privacy: .public)].\(phase, privacy: .public) stackDepth=\(nav.viewControllers.count) barH=\(barHeight)"
            )
        }
    }
}
