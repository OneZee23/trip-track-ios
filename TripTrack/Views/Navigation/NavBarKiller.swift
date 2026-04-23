import SwiftUI
import UIKit
import OSLog

private let navLog = Logger(subsystem: "com.triptrack", category: "nav")

/// Forces the underlying `UINavigationController` bar to stay invisible AND
/// zero-height so it can't cause the content to shift, plus keeps the
/// interactive swipe-back gesture working.
///
/// Why the previous approaches failed (per runtime logs):
///
/// 1. `.toolbar(.hidden)` — UIKit's push/pop animator re-sets
///    `navigationBar.isHidden = false` mid-transition even when the
///    controller-level `isNavigationBarHidden` stays true.
/// 2. `setNavigationBarHidden(true)` + `isHidden = true` only — UIKit's
///    animator also resets `alpha` back to 1.0 during push/pop, so even
///    the briefly-shown bar was visually painting 44pt of empty space.
/// 3. `alpha = 0` alone — same: UIKit restores it every transition.
///
/// Final fix: KVO observers on BOTH `isHidden` and `alpha`, synchronously
/// reverting them when UIKit toggles them. Plus `additionalSafeAreaInsets`
/// -44pt on the hosting VC so even during the brief flash window the bar
/// doesn't contribute safe-area space, preventing content from shifting.
struct NavBarKiller: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ vc: Controller, context: Context) {}

    final class Controller: UIViewController {
        private var hiddenObserver: NSKeyValueObservation?
        private var alphaObserver: NSKeyValueObservation?

        override func loadView() {
            let v = UIView()
            v.backgroundColor = .clear
            v.isUserInteractionEnabled = false
            view = v
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            hideBar(phase: "didMove")
            attachObservers()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            hideBar(phase: "willAppear")
            attachObservers()
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

        /// Observe `isHidden` and `alpha` — revert UIKit transition-induced
        /// toggles synchronously before the next paint. Both are KVO-
        /// compliant on `UINavigationBar`.
        private func attachObservers() {
            guard let bar = navigationController?.navigationBar else { return }
            if hiddenObserver == nil {
                hiddenObserver = bar.observe(\.isHidden, options: [.new]) { bar, change in
                    guard change.newValue == false else { return }
                    bar.isHidden = true
                    navLog.debug("kvo: bar unhidden — reverted")
                }
            }
            if alphaObserver == nil {
                alphaObserver = bar.observe(\.alpha, options: [.new]) { bar, change in
                    guard let new = change.newValue, new > 0 else { return }
                    bar.alpha = 0
                    navLog.debug("kvo: bar alpha=\(new) — reverted to 0")
                }
            }
        }

        private func hideBar(phase: String) {
            let nav = navigationController
            let barVisibleBefore = nav.map { !$0.isNavigationBarHidden }
            let barSubviewHiddenBefore = nav.map { $0.navigationBar.isHidden }
            let alphaBefore = nav.map { $0.navigationBar.alpha }

            nav?.setNavigationBarHidden(true, animated: false)
            nav?.navigationBar.isHidden = true
            nav?.navigationBar.alpha = 0
            // Negative top inset cancels the nav bar's 44pt safe-area
            // contribution — even if UIKit momentarily restores `isHidden`
            // and `alpha`, our content doesn't shift down because the bar
            // is treated as occupying zero safe-area space.
            if let bar = nav?.navigationBar {
                let barHeight = bar.frame.height
                nav?.additionalSafeAreaInsets = UIEdgeInsets(
                    top: -barHeight, left: 0, bottom: 0, right: 0,
                )
            }

            navLog.debug(
                "killer[\(ObjectIdentifier(self).hashValue, privacy: .public)].\(phase, privacy: .public) nav=\(nav != nil) barVisible=\(barVisibleBefore?.description ?? "nil", privacy: .public) isHidden=\(barSubviewHiddenBefore?.description ?? "nil", privacy: .public) alpha=\(alphaBefore?.description ?? "nil", privacy: .public) stackDepth=\(nav?.viewControllers.count ?? -1)"
            )
        }

        deinit {
            hiddenObserver?.invalidate()
            alphaObserver?.invalidate()
        }
    }
}
