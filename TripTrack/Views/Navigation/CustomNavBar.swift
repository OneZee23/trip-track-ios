import SwiftUI

/// Custom top bar rendered as a `safeAreaInset` above content in views that
/// hide the system navigation bar. Replaces the system bar because SwiftUI
/// briefly reverts it to default state ("← Back") during deep pop animations
/// inside sheet-hosted NavigationStacks, no matter how many hidden-flags we
/// set. Pair with `.toolbar(.hidden, for: .navigationBar)` on the host view.
/// Explicit override for `CustomNavBar`'s automatic sheet detection.
/// `nil` (default) = decide from `\.isPresented`. `PreviewNavigator` sets
/// `false` because it runs inside a `fullScreenCover` — presented, but with
/// a real status bar above it and no grabber, so it wants the canon inset.
private struct NavBarInSheetKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var navBarInSheet: Bool? {
        get { self[NavBarInSheetKey.self] }
        set { self[NavBarInSheetKey.self] = newValue }
    }
}

struct CustomNavBar<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.colorScheme) private var scheme
    /// True for anything inside a sheet / fullScreenCover; propagates down
    /// through the presented NavigationStack to pushed destinations.
    @Environment(\.isPresented) private var isPresented
    @Environment(\.navBarInSheet) private var inSheetOverride

    private var isInSheet: Bool { inSheetOverride ?? isPresented }

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
                NavBackButton()
                Spacer()
                trailing()
            }
        }
        .padding(.horizontal, 14)
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
    init(title: String) {
        self.title = title
        self.trailing = { EmptyView() }
    }
}
