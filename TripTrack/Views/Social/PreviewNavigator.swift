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

            // Root — always mounted; masked by pushed layers above.
            PublicProfileView(
                accountId: rootAccountId,
                preloaded: nil,
                onClose: onCloseSheet,
                pushPath: $path,
            )
            .zIndex(0)

            // Each pushed destination stacks on its own z-layer with a
            // slide-in/out transition.
            ForEach(Array(path.enumerated()), id: \.offset) { index, dest in
                destinationView(for: dest)
                    .environment(\.previewPop, popAction)
                    .background(c.bg)  // opaque so the layer below is hidden
                    .zIndex(Double(index + 1))
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.28), value: path.count)
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
        path.removeLast()
    }
}
