import SwiftUI
import UIKit

/// Forces the underlying `UINavigationController` to hide its bar AND keeps
/// the interactive swipe-back gesture working. Fixes two SwiftUI quirks
/// that `.toolbar(.hidden, for: .navigationBar)` cannot:
///
/// 1. **Pop-transition flash**: `.toolbar(.hidden)` is a per-destination
///    SwiftUI preference that UIKit crossfades across push/pop. During the
///    ~0.35s transition the system bar is briefly driven by whichever
///    preference hasn't resolved yet, producing the "blue ← Back" flash
///    users see. `setNavigationBarHidden(true, animated: false)` called in
///    `viewWillAppear` + re-asserted every `viewDidLayoutSubviews` pass
///    kills the bar at UIKit level, before SwiftUI's diff runs.
///
/// 2. **Swipe-back disabled**: hiding the nav bar also detaches the
///    default delegate of `interactivePopGestureRecognizer`. Setting
///    delegate to nil + re-enabling the recognizer restores the gesture.
///
/// Use via `.background(NavBarKiller())`. Safe only in nav stacks where
/// every pushed view wants the bar hidden — mixing with system-bar views
/// in the same stack will fight. `CustomNavBar` wires this in so callers
/// get both behaviors for free.
struct NavBarKiller: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ vc: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            navigationController?.setNavigationBarHidden(true, animated: false)
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            // Re-assert after every layout pass — pop transitions re-show
            // the bar between `viewWillAppear` on the incoming view and
            // SwiftUI applying its `.toolbar(.hidden)` preference. This
            // closes that race.
            navigationController?.setNavigationBarHidden(true, animated: false)
        }
    }
}
