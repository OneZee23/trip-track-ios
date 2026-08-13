import SwiftUI

/// Launch-time recovery prompt (Figma 505:119): the app closed mid-recording;
/// the route was preserved. Two ways out — Continue or Finish&Save. There is
/// deliberately NO discard and NO swipe-dismiss: non-junk orphans are always
/// preserved (dismissing would be an implicit discard).
struct RecoveryPromptSheet: View {
    @EnvironmentObject private var mapVM: MapViewModel
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.08))
                    .frame(width: 74, height: 74)
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.top, 28)
            .padding(.bottom, 16)

            Text(AppStrings.recoveryTitle(lang.language))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(c.text)
                .padding(.bottom, 8)

            Text(AppStrings.recoveryBody(lang.language))
                .font(.system(size: 14))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
                .padding(.bottom, 14)

            // «Восстановлено · 12.4 км · 0:23»
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                Text("\(AppStrings.recoveryChip(lang.language)) · \(String(format: "%.1f", mapVM.recoveryDistanceKm)) \(AppStrings.km(lang.language)) · \(mapVM.recoveryDuration)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(AppTheme.accent.opacity(0.1)))
            .padding(.bottom, 22)

            VStack(spacing: 10) {
                Button {
                    Haptics.success()
                    mapVM.continueRecoveredTrip()
                } label: {
                    Text(AppStrings.recoveryContinue(lang.language))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("recovery_continue")

                Button {
                    Haptics.tap()
                    mapVM.finishRecoveredTrip()
                } label: {
                    Text(AppStrings.recoveryFinish(lang.language))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(c.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("recovery_finish")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(c.bg)
        .contentSizedSheet()
        // No `presentationCornerRadius` override: on iOS 26 a sheet is a card
        // that floats inset from the screen, and forcing the radius left its
        // bottom corners squared off against the screen edge — the reported
        // «обрезанная карточка». The system radius is correct on both.
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
    }
}
