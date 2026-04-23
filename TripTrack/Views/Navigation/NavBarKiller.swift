import SwiftUI
import UIKit

/// Forces the underlying `UINavigationController` to hide its bar AND keeps
/// the interactive swipe-back gesture working. Fixes two SwiftUI quirks
/// that `.toolbar(.hidden, for: .navigationBar)` cannot:
///
/// 1. **Pop-transition flash**: `.toolbar(.hidden)` is a per-destination
///    SwiftUI preference that UIKit crossfades across push/pop. During
///    transitions — especially rapid ones — the system bar is briefly
///    driven by whichever preference hasn't resolved yet, producing the
///    "blue ← Back" flash. We re-assert `setNavigationBarHidden` in every
///    lifecycle callback (will/didAppear, willLayout/didLayoutSubviews,
///    didMove) to close every race window.
///
/// 2. **Swipe-back disabled**: hiding the nav bar detaches the default
///    delegate of `interactivePopGestureRecognizer`. Setting delegate to
///    nil + re-enabling restores the gesture.
///
/// The hosted `UIViewController` uses a transparent view so it never
/// paints a visible rectangle over the host screen.
///
/// Use via `.background(NavBarKiller())`. Safe only in nav stacks where
/// every pushed view wants the bar hidden. `CustomNavBar` wires this in
/// so callers get both behaviors for free.
struct NavBarKiller: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ vc: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func loadView() {
            // Transparent placeholder — prevents the hosted VC from
            // painting a solid rect behind SwiftUI content, which was
            // showing up as a faint center strip on the Followers screen.
            let v = UIView()
            v.backgroundColor = .clear
            v.isUserInteractionEnabled = false
            view = v
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            hideBar()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            hideBar()
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            hideBar()
        }

        override func viewWillLayoutSubviews() {
            super.viewWillLayoutSubviews()
            hideBar()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            hideBar()
        }

        private func hideBar() {
            // `isHidden = true` plus `setNavigationBarHidden` to catch
            // both the property- and method-driven UIKit paths — rapid
            // push/pop cycles otherwise let one or the other flicker on.
            navigationController?.navigationBar.isHidden = true
            navigationController?.setNavigationBarHidden(true, animated: false)
        }
    }
}
