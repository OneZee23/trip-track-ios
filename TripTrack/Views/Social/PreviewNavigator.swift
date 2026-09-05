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

/// Pure-SwiftUI stack navigator for the two SHEET flows that chain social
/// destinations (profile → followers → profile → …): the companions roster
/// and the comments screen, both of which open a profile from inside a sheet
/// via `fullScreenCover`. Replaces `NavigationStack` entirely so UIKit's
/// `UINavigationBar` is never in the picture — the only way to kill the
/// nav-bar flash that SwiftUI's NavigationStack exhibits at depth 4+.
///
/// NOT used by the «Я» tab any more. «Как видят другие» is an ordinary pushed
/// screen on `ProfileView`'s own `NavigationStack` (canon 580:438), and the
/// self-preview banner this navigator used to stack above it — an orange strip
/// with a «Готово» pill — went with the cover: that chrome existed only
/// because a cover has no nav bar. The «you are looking at your own profile»
/// cue is a CARD inside `PublicProfileView`'s content now, which is where
/// canon draws it and which every host of this navigator gets for free.
///
/// Depth capped at `ProfilePreviewDest.previewDepthCap` via `cappedAppend`.
/// At root (empty path) we do NOT inject `\.previewPop` so `NavBackButton`
/// falls through to `\.dismiss`, which closes the presenting sheet.
struct PreviewNavigator: View {
    @EnvironmentObject private var mapVM: MapViewModel
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
            c.bg.ignoresSafeArea()

            // Only the topmost view is mounted — key fix for the nav-bar
            // flash bug; rendering all layers makes SwiftUI animate
            // intermediate states and exposes unstyled chrome.
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
        case .publicStats(let id, let name):
            // Тот же StatsScreenView. Меняется только источник поездок —
            // форка экрана нет, и правка статистики меняет оба места сразу.
            StatsScreenView(
                tripManager: mapVM.tripManager,
                source: RemoteTripSource(accountId: id),
                ownerName: name
            )
        case .publicMap(let id, let name):
            PublicMapView(accountId: id, ownerName: name)
        case .publicGarage(let id, let name):
            PublicGarageView(accountId: id, ownerName: name)
        case .publicVehicle(let id, let vid, let name):
            PublicVehicleView(accountId: id, vehicleId: vid, ownerName: name)
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
