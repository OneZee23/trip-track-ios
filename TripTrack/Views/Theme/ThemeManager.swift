import SwiftUI
// Not a view — this reaches for the window itself. CLAUDE.md's «no UIKit in
// SwiftUI views» rule is about views; there is no SwiftUI way to set a window's
// interface style or to cross-fade one.
import UIKit

final class ThemeManager: ObservableObject {
    enum Mode: String, CaseIterable {
        case dark, light, system
    }

    @Published var mode: Mode {
        didSet {
            guard mode != oldValue else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: "appThemeMode")
            Self.paint(mode, animated: true)
        }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: "appThemeMode"),
           let m = Mode(rawValue: saved) {
            self.mode = m
        } else {
            self.mode = .system
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch mode {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }

    /// Paint the saved theme onto the window without animating it.
    ///
    /// Call once the window exists (the app root's `onAppear`): `init` runs
    /// before SwiftUI has made one, so the `didSet` path below has nothing to
    /// write to on a cold launch.
    func applyToWindows() {
        Self.paint(mode, animated: false)
    }

    // MARK: - Window override

    /// Sets `overrideUserInterfaceStyle` on every window, cross-fading it.
    ///
    /// Two reasons this is done to the WINDOW and not left to
    /// `preferredColorScheme` alone:
    ///
    ///  • `preferredColorScheme` stops at a presentation boundary, so every
    ///    sheet had to re-apply it by hand — and each of those hosting
    ///    controllers updates on its own SwiftUI pass. Switching the theme
    ///    from the picker repainted the page behind it a frame before the
    ///    picker itself, which is exactly the dark sheet-over-light-page flash
    ///    that was reported. A window override lands on the window's trait
    ///    collection, and every controller presented in it — sheets, covers,
    ///    the dialog layer — inherits the same change in the same pass.
    ///
    ///  • It gives us somewhere to hang the transition. A colour scheme change
    ///    is not animatable in SwiftUI: the palette is read at render time and
    ///    the whole screen simply swaps between two frames. `UIView.transition`
    ///    snapshots the window, applies the change, and cross-fades the
    ///    snapshot into the new render — one dissolve across the entire app
    ///    instead of a hard cut.
    private static func paint(_ mode: Mode, animated: Bool) {
        let style: UIUserInterfaceStyle
        switch mode {
        case .dark: style = .dark
        case .light: style = .light
        // NOT `.light`: unspecified is what hands the window back to the
        // phone's own setting, which is the whole meaning of «Системная».
        case .system: style = .unspecified
        }

        // Looked up rather than injected: this is called from a `didSet` on a
        // store that no view owns, and the same lookup already backs
        // `ContentSizedSheet.bottomInset`.
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)

        for window in windows where window.overrideUserInterfaceStyle != style {
            guard animated else {
                window.overrideUserInterfaceStyle = style
                continue
            }
            UIView.transition(
                with: window,
                duration: 0.28,
                // `allowUserInteraction` because a quarter-second of a dead
                // screen after a tap reads as a hang; `allowAnimatedContent`
                // so the live view animates through the dissolve instead of
                // both sides being frozen snapshots.
                options: [.transitionCrossDissolve, .allowUserInteraction, .allowAnimatedContent],
                animations: { window.overrideUserInterfaceStyle = style }
            )
        }
    }
}
