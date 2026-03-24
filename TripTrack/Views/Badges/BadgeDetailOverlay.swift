import SwiftUI

struct BadgeDetailOverlay: View {
    let badge: Badge
    let isUnlocked: Bool
    let language: LanguageManager.Language
    let colorScheme: ColorScheme
    var earnCount: Int? = nil
    let onDismiss: () -> Void
    @State private var appear = false

    var body: some View {
        let c = AppTheme.colors(for: colorScheme)
        let isRu = language == .ru

        ZStack {
            Color.black.opacity(appear ? 0.4 : 0)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 16) {
                // Large badge icon
                ZStack {
                    if isUnlocked {
                        Circle()
                            .fill(badge.color.opacity(0.08))
                            .frame(width: 120, height: 120)
                        Circle()
                            .stroke(badge.color.opacity(0.2), lineWidth: 2)
                            .frame(width: 110, height: 110)
                    }

                    Circle()
                        .fill(isUnlocked ? badge.color.opacity(0.15) : c.cardAlt)
                        .frame(width: 88, height: 88)

                    if isUnlocked {
                        Image(systemName: badge.icon)
                            .font(.system(size: 40))
                            .foregroundStyle(badge.color)
                    } else if badge.isHidden {
                        Image(systemName: "questionmark")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(c.textTertiary)
                    } else {
                        Image(systemName: badge.icon)
                            .font(.system(size: 40))
                            .foregroundStyle(c.textTertiary.opacity(0.5))
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(c.textTertiary)
                    }
                }

                Text(isUnlocked || !badge.isHidden ? badge.title(language) : "???")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(c.text)

                Text(isUnlocked || !badge.isHidden
                    ? badge.description(language)
                    : (isRu ? "Скрытое достижение" : "Hidden achievement"))
                    .font(.system(size: 14))
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)

                // Status pill
                HStack(spacing: 5) {
                    Image(systemName: isUnlocked ? "checkmark.circle.fill" : "lock.fill")
                    if isUnlocked, badge.isRepeatable, let count = earnCount, count > 0 {
                        Text(AppStrings.earnedTimes(language, count: count))
                            .font(.system(size: 13, weight: .semibold))
                    } else {
                        Text(isUnlocked
                            ? (isRu ? "Получено" : "Unlocked")
                            : (isRu ? "Не получено" : "Locked"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .foregroundStyle(isUnlocked ? AppTheme.green : c.textTertiary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    (isUnlocked ? AppTheme.green.opacity(0.1) : c.cardAlt),
                    in: Capsule()
                )

                Text(badge.category.title(language))
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(24)
            .padding(.top, 8)
            .frame(maxWidth: 300)
            .background(c.bg, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
            .scaleEffect(appear ? 1 : 0.8)
            .opacity(appear ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                appear = true
            }
        }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.2)) { appear = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            onDismiss()
        }
    }
}
