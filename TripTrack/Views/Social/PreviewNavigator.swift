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
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let popAction = path.isEmpty ? nil : PreviewPopAction { popTop() }

        ZStack {
            c.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Mode indicator for self-preview only (the user tapped their
                // own avatar/header in the Profile tab). Persistent banner
                // explains "you're in preview" — the screen looks nearly
                // identical to the Profile tab and without this users get
                // disoriented (NN/g heuristic #6: same-looking modes need
                // explicit recognition signals; LinkedIn's "View as" pattern).
                if isSelfPreview {
                    selfPreviewBanner(c)
                }

                // Only the topmost view is mounted — key fix for the
                // nav-bar flash bug; rendering all layers makes SwiftUI
                // animate intermediate states and exposes unstyled chrome.
                currentView(rootBg: c)
                    .id(path.count)
            }
        }
        .environment(\.previewPop, popAction)
        // We're a fullScreenCover: `\.isPresented` is true, but there's a
        // real status bar above us and no grabber, so the nav bars here
        // keep the canon 8pt inset instead of the sheet clearance.
        .environment(\.navBarInSheet, false)
    }

    private var isSelfPreview: Bool {
        guard let myId = TokenStore.shared.accountId else { return false }
        if case .profile(let id, _) = rootDest, id == myId { return true }
        return false
    }

    private func selfPreviewBanner(_ c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru
        return HStack(spacing: 10) {
            Image(systemName: "eye.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(isRu
                 ? "Предпросмотр — так Ваш профиль видят другие"
                 : "Preview — how others see your profile")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            Button {
                Haptics.tap()
                onCloseSheet()
            } label: {
                Text(isRu ? "Готово" : "Done")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.22), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        // Extend the accent fill up under the status bar so the banner
        // visually anchors to the top edge — `.ignoresSafeArea(edges: .top)`
        // applied to the background only (not the content) keeps text
        // padding correct while the colour bleeds upward.
        .background(AppTheme.accent.ignoresSafeArea(edges: .top))
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
        case .trip, .socialTrip:
            // Trip destinations only belong to Feed's NavigationStack. If they
            // somehow ended up here (in the profile-preview sheet) just render
            // nothing rather than crash — and log so we notice the misroute.
            EmptyView()
                .onAppear {
                    NavFlashDebug.log.debug("PreviewNavigator got trip dest — ignoring")
                }
        }
    }

    private func popTop() {
        guard !path.isEmpty else { return }
        NavFlashDebug.log.debug("PreviewNavigator.popTop depth \(self.path.count)→\(self.path.count - 1)")
        path.removeLast()
    }
}
