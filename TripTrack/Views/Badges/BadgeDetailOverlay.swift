import SwiftUI

/// The badge card (Figma 117:1547).
struct BadgeDetailOverlay: View {
    let badge: Badge
    let isUnlocked: Bool
    let language: LanguageManager.Language
    let colorScheme: ColorScheme
    var earnCount: Int? = nil
    var lastEarnedDate: Date? = nil
    /// What the owner actually did to earn it («47.3 км») — the canon puts the
    /// personal number under the generic rule, because «проедьте 42.2 км» is
    /// the badge and «47.3 км» is the memory.
    var recordValue: String? = nil
    /// Trip this badge was earned on, for the «Получен … · Дача и обратно» line.
    var earnedOnTripTitle: String? = nil
    /// Present to offer the canon's «Поделиться» button.
    var onShare: (() -> Void)? = nil
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

                if isUnlocked, let recordValue {
                    Text(recordValue)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(badge.color)
                }

                if isUnlocked, let date = lastEarnedDate {
                    Text(AppStrings.badgeEarnedOn(
                        language,
                        date: date,
                        tripTitle: earnedOnTripTitle
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                }

                Text(badge.category.title(language))
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)

                if isUnlocked, let onShare {
                    Button {
                        Haptics.tap()
                        onShare()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                            Text(AppStrings.share(language))
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.accent))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                    .accessibilityIdentifier("badge_share")
                }
            }
            .padding(24)
            .padding(.top, 8)
            .frame(maxWidth: 300)
            .overlay(alignment: .topTrailing) {
                Button { close() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(c.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(c.cardAlt))
                }
                .buttonStyle(.plain)
                .padding(12)
                .accessibilityIdentifier("badge_close")
                .accessibilityLabel(AppStrings.close(language))
            }
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
