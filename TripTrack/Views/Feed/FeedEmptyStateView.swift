import SwiftUI

struct FeedEmptyStateView: View {
    let hasFilters: Bool
    let onStartTrip: () -> Void
    let onResetFilters: () -> Void
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @State private var iconScale: CGFloat = 0.8

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(spacing: 16) {
            Spacer()

            if hasFilters {
                // No trips matching filter
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(c.textTertiary)
                    .scaleEffect(iconScale)

                Text(AppStrings.noResults(lang.language))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(c.text)

                Text(AppStrings.tryOtherFilters(lang.language))
                    .font(.system(size: 14))
                    .foregroundStyle(c.textSecondary)

                Button {
                    Haptics.action()
                    onResetFilters()
                } label: {
                    Text(AppStrings.reset(lang.language))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(AppTheme.accent, in: Capsule())
                }
                .padding(.top, 4)
            } else {
                // No trips at all
                Image(systemName: "car.side")
                    .font(.system(size: 48))
                    .foregroundStyle(c.textTertiary)
                    .scaleEffect(iconScale)

                Text(AppStrings.timeToRide(lang.language))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(c.text)

                Text(AppStrings.recordAndBuild(lang.language))
                    .font(.system(size: 14))
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    Haptics.action()
                    onStartTrip()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                        Text(AppStrings.startTrip(lang.language))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(AppTheme.accent, in: Capsule())
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.1)) {
                iconScale = 1.0
            }
        }
    }
}
