import SwiftUI

/// Custom top bar rendered as a `safeAreaInset` above content in views that
/// hide the system navigation bar. Replaces the system bar because SwiftUI
/// briefly reverts it to default state ("← Back") during deep pop animations
/// inside sheet-hosted NavigationStacks, no matter how many hidden-flags we
/// set. Pair with `.toolbar(.hidden, for: .navigationBar)` on the host view.
/// Set to `true` by the few sheets that host `CustomNavBar` screens, so the
/// bar can clear the grabber (see `CustomNavBar.topInset`).
///
/// It has to be explicit. The obvious shortcut — `@Environment(\.isPresented)`
/// — is wrong: SwiftUI models a NavigationStack push as a presentation too
/// (that's why `\.dismiss` pops), so every pushed screen reported `true` and
/// got 12pt of sheet clearance it should not have. Measured: the profile
/// pushed from the feed sat at 82pt instead of the canon 70pt.
private struct NavBarInSheetKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var navBarInSheet: Bool {
        get { self[NavBarInSheetKey.self] }
        set { self[NavBarInSheetKey.self] = newValue }
    }
}

struct CustomNavBar<Trailing: View>: View {
    let title: String
    /// Sheet roots (Discover) have nothing to pop — they close from the
    /// trailing side, so they hide the back button rather than show a
    /// chevron that would really mean "dismiss".
    var showsBack: Bool = true
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.colorScheme) private var scheme
    @Environment(\.navBarInSheet) private var isInSheet

    /// Figma canon for every pushed screen that uses this bar (profile
    /// 117:943, Discover 117:275, Activity 117:1853): the 34pt control row
    /// is inset 8pt from the top, i.e. it clears the status bar by 8pt.
    ///
    /// A sheet has no status bar above it — its top edge is a hard rounded
    /// boundary and UIKit draws the grabber over the first 10pt of it. The
    /// canon 8pt there puts the row under the grabber and glued to the
    /// edge, so sheets get 10pt (grabber) + 10pt gap instead.
    private var topInset: CGFloat { isInSheet ? 20 : 8 }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        // ZStack keeps the title centered over the full width while leading
        // back button and trailing action sit in their own HStack overlay —
        // same layout model as `UINavigationBar` so long titles truncate
        // instead of pushing the trailing view off-screen.
        ZStack {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 64)

            HStack {
                if showsBack {
                    NavBackButton()
                }
                Spacer()
                trailing()
            }
        }
        // Canon insets the 34pt controls 10pt from the edge, but that was
        // drawn on a 360pt artboard — on a 440pt phone the same value puts
        // them on the curved glass, half inside the interactive-pop gesture
        // strip, which is what made them feel edge-glued and awkward to hit.
        // 20pt keeps the pair visually centred in the corner instead.
        .padding(.horizontal, 20)
        // See `topInset` — 8pt on pushed screens (canon), 20pt in sheets.
        .padding(.top, topInset)
        .padding(.bottom, 8)
        .frame(minHeight: 42 + topInset)
        .frame(maxWidth: .infinity)
        .background(c.bg)
        // Per-destination NavBarKiller in addition to any root-level one.
        // Two bodies better than one: during the push/pop handoff window,
        // if the outgoing killer is torn down but incoming hasn't fired
        // `viewWillAppear` yet, a root-attached killer (if the host added
        // one) keeps the bar down. Belt-and-suspenders.
        .background(NavBarKiller())
    }
}

extension CustomNavBar where Trailing == EmptyView {
    init(title: String, showsBack: Bool = true) {
        self.title = title
        self.showsBack = showsBack
        self.trailing = { EmptyView() }
    }
}
