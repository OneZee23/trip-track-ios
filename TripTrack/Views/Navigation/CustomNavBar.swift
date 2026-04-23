import SwiftUI

/// Custom top bar rendered as a `safeAreaInset` above content in views that
/// hide the system navigation bar. Works around a SwiftUI quirk where the
/// system nav bar briefly reverts to its default state ("← Followers" back
/// button with borrowed title) during push/pop animations — replacing it
/// entirely keeps chrome stable through transitions.
///
/// Pair with `.toolbar(.hidden, for: .navigationBar)` on the hosting view.
struct CustomNavBar<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        HStack(spacing: 12) {
            NavBackButton()
            Spacer(minLength: 8)
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(c.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(c.bg)
    }
}

extension CustomNavBar where Trailing == EmptyView {
    init(title: String) {
        self.title = title
        self.trailing = { EmptyView() }
    }
}
