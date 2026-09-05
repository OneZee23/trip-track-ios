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
    /// Canon runs TWO title sizes on pushed screens. Most carry the small bar
    /// («Мой профиль», «Страна»); the two collection screens — «Достижения»
    /// (895:365) and «Статистика» (580:316) — are headed by a 28pt display
    /// title, because they are destinations you land on rather than steps you
    /// pass through.
    var largeTitle: Bool = false
    /// Вторая строка под заголовком. Появилась ради ЧУЖИХ экранов (0.6.3):
    /// «Статистика» своя и «Статистика» Александра отличаются только этим
    /// именем, а без него две страницы с разными числами выглядят одинаково.
    /// `nil` на всех остальных экранах — их вёрстка не меняется.
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.colorScheme) private var scheme
    @Environment(\.navBarInSheet) private var isInSheet

    /// Figma canon for every pushed screen that uses this bar (profile
    /// 117:943, Discover 117:275, Activity 117:1853) insets the control row
    /// 8pt from the top, i.e. it clears the status bar by 8pt.
    ///
    /// A sheet has no status bar above it — its top edge is a hard rounded
    /// boundary and UIKit draws the grabber over the first 10pt of it. The
    /// canon 8pt there puts the row under the grabber and glued to the
    /// edge, so sheets get 10pt (grabber) + 10pt gap instead.
    private var topInset: CGFloat { isInSheet ? 20 : 10 }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        // ZStack keeps the title centered over the full width while leading
        // back button and trailing action sit in their own HStack overlay —
        // same layout model as `UINavigationBar` so long titles truncate
        // instead of pushing the trailing view off-screen.
        ZStack {
            // 18pt, not the artboard's 15. See `NavCircleIcon.diameter` for
            // why the whole bar was drawn a size too small for the phones it
            // ships to; a 15pt title next to 40pt controls reads as a caption.
            // iOS draws its own nav titles at 17pt semibold — this sits a
            // hair above that because the bar carries no hairline to separate
            // it from the content below.
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: largeTitle ? 28 : 18, weight: .heavy))
                    .tracking(largeTitle ? -0.56 : 0)
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                    .minimumScaleFactor(largeTitle ? 0.7 : 1)
                    .truncationMode(.tail)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            // Clear both controls (40pt + 20pt inset) so a long title
            // truncates instead of colliding with them.
            .padding(.horizontal, 72)

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
        .padding(.bottom, 12)
        .frame(minHeight: NavCircleIcon.diameter + 12 + topInset)
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
    init(
        title: String,
        showsBack: Bool = true,
        largeTitle: Bool = false,
        subtitle: String? = nil
    ) {
        self.title = title
        self.showsBack = showsBack
        self.largeTitle = largeTitle
        self.subtitle = subtitle
        self.trailing = { EmptyView() }
    }
}
