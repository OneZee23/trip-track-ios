import SwiftUI
import UIKit
import OSLog

private let navLog = Logger(subsystem: "com.triptrack", category: "nav")

/// Forces the underlying `UINavigationController` bar to stay invisible and
/// keeps the interactive swipe-back gesture working.
///
/// Why this isn't just `.toolbar(.hidden, for: .navigationBar)`:
/// UIKit's push/pop animator re-sets `navigationBar.isHidden = false` mid-
/// transition even when `isNavigationBarHidden` is true at the controller
/// level — the two states diverge briefly, producing the "← Back" flash
/// described on Apple forums. We counter with three layers:
///
/// 1. `setNavigationBarHidden(true)` every lifecycle callback (best-effort
///    at the controller API level).
/// 2. `navigationBar.alpha = 0` — UIKit's transitions animate `isHidden`
///    but don't touch `alpha`, so even when the bar is technically visible
///    it paints nothing.
/// 3. KVO on `navigationBar.isHidden`: if UIKit ever flips it to false
///    during a transition, we flip it back synchronously.
struct NavBarKiller: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ vc: Controller, context: Context) {}

    final class Controller: UIViewController {
        private var hiddenObserver: NSKeyValueObservation?

        override func loadView() {
            let v = UIView()
            v.backgroundColor = .clear
            v.isUserInteractionEnabled = false
            view = v
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            hideBar(phase: "didMove")
            attachObserver()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            hideBar(phase: "willAppear")
            attachObserver()
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            hideBar(phase: "didAppear")
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            hideBar(phase: "willDisappear")
        }

        override func viewWillLayoutSubviews() {
            super.viewWillLayoutSubviews()
            hideBar(phase: "willLayout")
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            hideBar(phase: "didLayout")
        }

        /// Attach a KVO observer that instantly re-hides the bar if UIKit's
        /// transition animator toggles `isHidden = false`. Observer lives
        /// on this VC instance and is released with it — each NavBarKiller
        /// gets its own, so there's always at least one observer active
        /// whenever any NavBarKiller-using destination is on-stack.
        private func attachObserver() {
            guard hiddenObserver == nil, let bar = navigationController?.navigationBar else { return }
            hiddenObserver = bar.observe(\.isHidden, options: [.new]) { bar, change in
                guard change.newValue == false else { return }
                // Synchronous revert — UIKit's animator toggled the subview
                // visible mid-transition. Flip back before the next paint.
                bar.isHidden = true
                navLog.debug("kvo: bar unhidden — reverted")
            }
        }

        private func hideBar(phase: String) {
            let nav = navigationController
            let barVisibleBefore = nav.map { !$0.isNavigationBarHidden }
            let barSubviewHiddenBefore = nav.map { $0.navigationBar.isHidden }
            let alphaBefore = nav.map { $0.navigationBar.alpha }

            nav?.setNavigationBarHidden(true, animated: false)
            nav?.navigationBar.isHidden = true
            // Alpha-zero is the load-bearing part: even if UIKit's animator
            // flips `isHidden` back to false between our callbacks, an
            // `alpha = 0` bar paints nothing on screen.
            nav?.navigationBar.alpha = 0

            navLog.debug(
                "killer[\(ObjectIdentifier(self).hashValue, privacy: .public)].\(phase, privacy: .public) nav=\(nav != nil) barVisible=\(barVisibleBefore?.description ?? "nil", privacy: .public) isHidden=\(barSubviewHiddenBefore?.description ?? "nil", privacy: .public) alpha=\(alphaBefore?.description ?? "nil", privacy: .public) stackDepth=\(nav?.viewControllers.count ?? -1)"
            )
        }

        deinit {
            hiddenObserver?.invalidate()
        }
    }
}
