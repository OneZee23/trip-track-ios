import SwiftUI

/// Environment action that pops the top of a `PreviewNavigator` stack.
/// When non-nil, `NavBackButton` prefers calling this over the built-in
/// `\.dismiss` — lets our pure-SwiftUI navigator handle back taps without
/// sending the whole fullScreenCover away.
struct PreviewPopAction {
    let pop: () -> Void
    func callAsFunction() { pop() }
}

private struct PreviewPopKey: EnvironmentKey {
    static let defaultValue: PreviewPopAction? = nil
}

extension EnvironmentValues {
    var previewPop: PreviewPopAction? {
        get { self[PreviewPopKey.self] }
        set { self[PreviewPopKey.self] = newValue }
    }
}

/// Pure-SwiftUI stack navigator used by every flow that chains social
/// destinations (profile → followers → profile → …). Replaces
/// `NavigationStack` entirely so UIKit's `UINavigationBar` is never in the
/// picture — the only way to kill the nav-bar flash that SwiftUI's
/// NavigationStack exhibits at depth 4+.
///
/// Depth capped at `ProfilePreviewDest.previewDepthCap` via `cappedAppend`.
/// At root (empty path) we do NOT inject `\.previewPop` so `NavBackButton`
/// falls through to `\.dismiss`, which closes the presenting sheet.
struct PreviewNavigator: View {
    /// The root destination — shown when `path` is empty. Generalizing this
    /// (vs. hardcoding `PublicProfileView`) lets the same navigator host the
    /// ProfileView → FollowListView flow without a `NavigationStack`.
    let rootDest: ProfilePreviewDest
    @Binding var path: [ProfilePreviewDest]
    let onCloseSheet: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let popAction = path.isEmpty ? nil : PreviewPopAction { popTop() }

        ZStack {
            // Opaque full-screen backdrop so transitioning content can't
            // reveal whatever was on screen before fullScreenCover opened.
            c.bg.ignoresSafeArea()

            // Only the topmost view is mounted — key fix for the flash bug:
            // if we always rendered all layers, SwiftUI's transition system
            // would animate each reveal/removal and open a brief window where
            // the incoming layer isn't fully laid out yet. Rendering only the
            // top means there's nothing to transition.
            // Trade-off: back-navigation re-creates the previous view,
            // re-running its `.task` — acceptable here because every view's
            // load is idempotent (guarded by `didInitialLoad`).
            currentView(rootBg: c)
                .id(path.count)
        }
        .environment(\.previewPop, popAction)
    }

    @ViewBuilder
    private func currentView(rootBg: AppTheme.Colors) -> some View {
        let top = path.last ?? rootDest
        let isRoot = path.isEmpty
        destinationView(for: top, isRoot: isRoot)
            .background(rootBg.bg)
    }

    @ViewBuilder
    private func destinationView(for dest: ProfilePreviewDest, isRoot: Bool) -> some View {
        switch dest {
        case .profile(let id, let author):
            PublicProfileView(
                accountId: id,
                preloaded: author,
                onClose: isRoot ? onCloseSheet : nil,
                pushPath: $path,
            )
        case .followList(let id, let mode):
            FollowListView(
                accountId: id,
                mode: mode,
                onClose: isRoot ? onCloseSheet : nil,
                pushPath: $path,
            )
        }
    }

    private func popTop() {
        guard !path.isEmpty else { return }
        NavFlashDebug.log.debug("PreviewNavigator.popTop depth \(self.path.count)→\(self.path.count - 1)")
        path.removeLast()
    }
}
