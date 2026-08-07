import SwiftUI

/// The full discussion, opened from «Все ›» on the trip detail.
///
/// Same `TripCommentsSection` the detail embeds, just not in preview mode:
/// one implementation of a comment row, one composer, one delete flow. What
/// changes is the depth — here every comment is loaded and paginated, and
/// replying is available, which is why the preview can stay three clean
/// rows (canon 549:129).
struct TripCommentsScreen: View {
    let tripId: UUID
    let isTripOwner: Bool
    var initialCount: Int = 0
    var onError: (String) -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(AppStrings.commentsTitleN(lang.language, initialCount))
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    NavCircleIcon(systemImage: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.closeSheet(lang.language))
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            ScrollView {
                TripCommentsSection(
                    tripId: tripId,
                    isTripOwner: isTripOwner,
                    initialCount: initialCount,
                    onError: onError,
                    isPreview: false
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(c.bg)
        .dismissesKeyboardOnTapAnywhere()
        .presentationDragIndicator(.visible)
    }
}
