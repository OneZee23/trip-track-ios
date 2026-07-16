import SwiftUI

/// Placeholder for the future Groups feature (interest-based driving
/// communities). Tapping the Groups tab lands here; it explains what's
/// coming rather than showing an empty screen. The full "coming soon"
/// showcase (club catalog, notify-me) replaces this in the Groups stage
/// of the 6.1.0 redesign.
struct GroupsComingSoonView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        return ZStack {
            c.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(28)
                    .background(AppTheme.accent.opacity(0.12), in: Circle())

                Text(AppStrings.groupsComingTitle(lang.language))
                    .font(.title2.bold())
                    .foregroundStyle(c.text)
                    .multilineTextAlignment(.center)

                Text(AppStrings.groupsComingBody(lang.language))
                    .font(.subheadline)
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: 420)
        }
    }
}
