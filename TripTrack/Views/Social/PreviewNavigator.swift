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

/// Pure-SwiftUI stack navigator used by the "preview as others see you"
/// flow. Replaces `NavigationStack` entirely so UIKit's `UINavigationBar`
/// is never in the picture — only way to kill the nav-bar flash bug.
///
/// Transitions: horizontal slide for push/pop, mimicking iOS navigation.
/// Depth capped at `ProfilePreviewDest.previewDepthCap` via `cappedAppend`.
struct PreviewNavigator: View {
    let rootAccountId: UUID
    @Binding var path: [ProfilePreviewDest]
    let onCloseSheet: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let popAction = PreviewPopAction { popTop() }

        ZStack {
            // Opaque full-screen backdrop so transitioning content can't
            // reveal whatever was on screen before fullScreenCover opened.
            c.bg.ignoresSafeArea()

            // Only the topmost view is mounted — this is the key fix for
            // the persistent flash bug: if we always render all layers
            // (root + every pushed destination), SwiftUI's transition
            // system animates each reveal/removal which opens a brief
            // window where the incoming layer isn't fully laid out yet.
            // Rendering only the top means there's nothing to transition.
            // Trade-off: back-navigation re-creates the previous view,
            // re-running its `.task` — acceptable here because every
            // view's load is idempotent (guarded by `didInitialLoad`).
            currentView(rootBg: c)
                .id(path.count)  // force fresh view on level change
        }
        .environment(\.previewPop, popAction)
    }

    @ViewBuilder
    private func currentView(rootBg: AppTheme.Colors) -> some View {
        if let top = path.last {
            destinationView(for: top)
                .background(rootBg.bg)
        } else {
            PublicProfileView(
                accountId: rootAccountId,
                preloaded: nil,
                onClose: onCloseSheet,
                pushPath: $path,
            )
        }
    }

    @ViewBuilder
    private func destinationView(for dest: ProfilePreviewDest) -> some View {
        switch dest {
        case .profile(let id, let author):
            PublicProfileView(
                accountId: id, preloaded: author, pushPath: $path,
            )
        case .followList(let id, let mode):
            FollowListView(
                accountId: id, mode: mode, pushPath: $path,
            )
        }
    }

    private func popTop() {
        guard !path.isEmpty else { return }
        NavFlashDebug.log.debug("PreviewNavigator.popTop depth \(self.path.count)→\(self.path.count - 1)")
        path.removeLast()
    }
}
