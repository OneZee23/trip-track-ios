import SwiftUI
import UIKit

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
        private var watcher: NavBarFrameWatcher?
        private var hiddenObs: NSKeyValueObservation?
        private var alphaObs: NSKeyValueObservation?
        private var frameObs: NSKeyValueObservation?
        private lazy var selfTag: String = NavFlashDebug.tag(self)

        override func loadView() {
            let v = UIView()
            v.backgroundColor = .clear
            v.isUserInteractionEnabled = false
            view = v
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            log(phase: "didMove", parent: parent)
            blankTheBar(phase: "didMove")
            attachWatcherIfReady(phase: "didMove")
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            log(phase: "willAppear", animated: animated, coordinator: transitionCoordinator)
            blankTheBar(phase: "willAppear")
            attachWatcherIfReady(phase: "willAppear")
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true

            // Hook transition coordinator — fires when the push/pop
            // animation genuinely starts/ends. Much more reliable than
            // guessing based on lifecycle alone.
            transitionCoordinator?.animate(alongsideTransition: { [weak self] ctx in
                guard let self else { return }
                NavFlashDebug.log.debug(
                    "killer[\(self.selfTag, privacy: .public)].coord.start isInteractive=\(ctx.isInteractive) isCancelled=\(ctx.isCancelled) dur=\(ctx.transitionDuration)"
                )
                self.blankTheBar(phase: "coord.start")
            }, completion: { [weak self] ctx in
                guard let self else { return }
                NavFlashDebug.log.debug(
                    "killer[\(self.selfTag, privacy: .public)].coord.end isCancelled=\(ctx.isCancelled)"
                )
                self.blankTheBar(phase: "coord.end")
            })
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            log(phase: "didAppear", animated: animated)
            blankTheBar(phase: "didAppear")
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            log(phase: "willDisappear", animated: animated, coordinator: transitionCoordinator)
            blankTheBar(phase: "willDisappear")
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            log(phase: "didDisappear", animated: animated)
            // Nothing to blank anymore — detach watcher to stop noise.
            watcher?.stop()
            watcher = nil
        }

        override func viewWillLayoutSubviews() {
            super.viewWillLayoutSubviews()
            blankTheBar(phase: "willLayout")
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            blankTheBar(phase: "didLayout")
        }

        // MARK: - Logging

        private func log(phase: String, animated: Bool? = nil, coordinator: UIViewControllerTransitionCoordinator? = nil, parent: UIViewController? = nil) {
            let nav = navigationController
            let depth = nav?.viewControllers.count ?? 0
            let top = NavFlashDebug.describe(nav?.topViewController)
            let navCls = nav.map { String(describing: type(of: $0)) } ?? "nil"
            let chain = NavFlashDebug.responderChain(from: view)
            let anim = animated.map { "\($0)" } ?? "-"
            let coordStr: String
            if let coordinator {
                coordStr = "coord{interactive=\(coordinator.isInteractive) cancelled=\(coordinator.isCancelled) dur=\(coordinator.transitionDuration)}"
            } else {
                coordStr = "coord=nil"
            }
            let parentStr = parent.map { NavFlashDebug.describe($0) } ?? "nil"
            NavFlashDebug.log.debug(
                "killer[\(self.selfTag, privacy: .public)].\(phase, privacy: .public) animated=\(anim, privacy: .public) depth=\(depth) top=\(top, privacy: .public) nav=\(navCls, privacy: .public) parent=\(parentStr, privacy: .public) \(coordStr, privacy: .public) chain=[\(chain, privacy: .public)]"
            )
        }

        private func attachWatcherIfReady(phase: String) {
            guard let nav = navigationController else { return }
            guard watcher == nil else { return }
            watcher = NavBarFrameWatcher(bar: nav.navigationBar, navController: nav, ownerTag: selfTag)
            watcher?.start()

            // Extra model-layer KVO so we can correlate model changes with
            // presentation-layer events the frame watcher catches.
            hiddenObs = nav.navigationBar.observe(\.isHidden, options: [.new, .old]) { [weak self] _, change in
                guard let self else { return }
                NavFlashDebug.log.debug(
                    "bar[\(self.selfTag, privacy: .public)].isHidden \(change.oldValue ?? false)→\(change.newValue ?? false)"
                )
            }
            alphaObs = nav.navigationBar.observe(\.alpha, options: [.new, .old]) { [weak self] _, change in
                guard let self else { return }
                NavFlashDebug.log.debug(
                    "bar[\(self.selfTag, privacy: .public)].alpha \(change.oldValue ?? 0)→\(change.newValue ?? 0)"
                )
            }
            frameObs = nav.navigationBar.observe(\.frame, options: [.new, .old]) { [weak self] _, change in
                guard let self, let new = change.newValue else { return }
                NavFlashDebug.log.debug(
                    "bar[\(self.selfTag, privacy: .public)].frame y=\(new.origin.y) h=\(new.size.height)"
                )
            }

            NavFlashDebug.log.debug(
                "killer[\(self.selfTag, privacy: .public)].watcher.attach phase=\(phase, privacy: .public)"
            )
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
        }
    }
}
