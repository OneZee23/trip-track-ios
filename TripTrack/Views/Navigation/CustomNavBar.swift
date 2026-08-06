import SwiftUI

/// Custom top bar rendered as a `safeAreaInset` above content in views that
/// hide the system navigation bar. Replaces the system bar because SwiftUI
/// briefly reverts it to default state ("← Back") during deep pop animations
/// inside sheet-hosted NavigationStacks, no matter how many hidden-flags we
/// set. Pair with `.toolbar(.hidden, for: .navigationBar)` on the host view.
struct CustomNavBar<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.colorScheme) private var scheme

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
        // Figma canon for every pushed screen that uses this bar (profile
        // 117:943, Discover 117:275, Activity 117:1853): a 50pt bar whose
        // 34pt control row is inset 8pt from the top, i.e. the controls
        // clear the status bar by 8pt. We rendered a 44pt bar with the row
        // centred (~5pt) — 6pt shorter and 3pt higher than the design, which
        // is what made the row read as glued to the top edge.
        .padding(.vertical, 8)
        .frame(minHeight: 50)
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
