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
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity)
        .background(c.bg)
        // Kill the UIKit-level nav bar and restore swipe-back. Pure
        // SwiftUI `.toolbar(.hidden)` crossfades across pop transitions
        // and briefly shows the system bar — `NavBarKiller` closes that
        // race by hiding at the UINavigationController layer instead.
        .background(NavBarKiller())
    }
}

extension CustomNavBar where Trailing == EmptyView {
    init(title: String) {
        self.title = title
        self.trailing = { EmptyView() }
    }
}
