import SwiftUI

/// The whole discussion, opened from the teaser on the trip detail.
///
/// Same `TripCommentsSection` the detail embeds, just not in preview mode:
/// one implementation of a row, one composer, one delete flow. What changes is
/// the depth — here everything is loaded and paginated, and replying lives.
///
/// A sheet rather than a pushed screen, deliberately: the trip stays behind it,
/// and getting in and out costs a swipe.
struct TripCommentsScreen: View {
    let tripId: UUID
    let isTripOwner: Bool
    var initialCount: Int = 0
    /// Opened by tapping the write row rather than the pill — come up with the
    /// keyboard, at .large, ready to type.
    var startFocused: Bool = false
    var onError: (String) -> Void

    @State private var detent: PresentationDetent = .medium

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
                    startFocused: startFocused,
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
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onAppear {
            // Typing needs the room; browsing does not.
            if startFocused { detent = .large }
        }
    }
}
