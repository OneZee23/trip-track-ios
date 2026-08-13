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
    /// The heading's «· N», kept live by the section below rather than frozen
    /// at whatever it was when the sheet opened.
    @State private var count: Int
    /// A signed-out viewer tapping the composer. Presented HERE, on top of
    /// this sheet, rather than handed back to the trip detail: the detail is
    /// behind a presented sheet and cannot put another one up over it, so
    /// routing it there would have offered sign-in and then shown nothing.
    @State private var signInPrompt: SignInPromptSheet.Action?

    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var auth = AuthService.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    init(
        tripId: UUID,
        isTripOwner: Bool,
        initialCount: Int = 0,
        startFocused: Bool = false,
        onError: @escaping (String) -> Void
    ) {
        self.tripId = tripId
        self.isTripOwner = isTripOwner
        self.initialCount = initialCount
        self.startFocused = startFocused
        self.onError = onError
        _count = State(initialValue: initialCount)
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(AppStrings.commentsTitleN(lang.language, count))
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
                    // Without this the composer down there was live for a
                    // signed-out viewer: they could type, send, and be told
                    // «Не удалось отправить комментарий» by a server that was
                    // never going to accept it.
                    onGuestInputTap: { signInPrompt = .comment },
                    onCountChange: { count = $0 },
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
        .sheet(item: $signInPrompt) { action in
            SignInPromptSheet(action: action)
                .environmentObject(lang)
                .environmentObject(auth)
                // Matched to whatever THIS sheet is rendering in: a sheet does
                // not inherit `preferredColorScheme`, and the two appearing in
                // different appearances one on top of the other is worse than
                // either choice on its own.
                .preferredColorScheme(scheme)
        }
        .onAppear {
            // Typing needs the room; browsing does not.
            if startFocused { detent = .large }
        }
    }
}
