import SwiftUI

/// An interactive try-on using the person's own identity, never invented stats.
struct ProPaywallHero: View {
    let name: String
    let avatarEmoji: String
    let onTap: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    static let background: ProfileBackground = .plusNebula
    static let frame: AvatarFrame = .gold

    var body: some View {
        Button {
            Haptics.tap()
            onTap()
        } label: {
            HStack(spacing: 16) {
                Text(avatarEmoji)
                    .font(.inter(29))
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.16), in: Circle())
                    .avatarFrame(Self.frame, lineWidth: 3)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(name)
                            .font(.interScaled(20, weight: .bold, relativeTo: .title3))
                            .fixedSize(horizontal: false, vertical: true)
                        ProBadge(height: 16)
                    }
                    Text(AppStrings.proTryYourStyle(lang.language))
                        .font(.interScaled(12, weight: .medium, relativeTo: .caption))
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(minHeight: 104)
            .background(Self.background.view().overlay(.black.opacity(0.18)))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("pro_hero")
        .accessibilityElement(children: .combine)
    }
}
