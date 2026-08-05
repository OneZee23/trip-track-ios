import SwiftUI

/// iMessage/Telegram-style reaction picker: blurred backdrop + floating
/// capsule with the available emoji. Presented as a full-screen overlay
/// when the user long-presses a trip card.
///
/// Layout: the capsule wraps an `HStack` in a horizontal `ScrollView` so
/// growing the emoji set in the future (currently 8) doesn't blow past
/// the device width. On phones where everything fits, the scroll never
/// fires — `.fixedSize` collapses the capsule to content width.
struct ReactionPickerOverlay: View {
    let currentReaction: String?
    var onPick: (String) -> Void
    var onDismiss: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        ZStack {
            // Blurred dim backdrop — tap to dismiss.
            Color.black.opacity(0.35)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    dismiss()
                }

            // Floating capsule (Figma 117:318 — glass chrome). Inner scroll
            // only fires when emoji set exceeds device width — at 8 × 40pt
            // + spacing/padding the capsule is ~370pt, fits every iPhone
            // since SE.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(ReactionEmoji.all.enumerated()), id: \.offset) { index, emoji in
                        pill(emoji: emoji, index: index, c: c)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .frame(maxWidth: UIScreen.main.bounds.width - 24)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                Capsule()
                    .fill(c.glass)
            }
            .overlay(
                Capsule()
                    .stroke(
                        scheme == .dark ? c.glassBorder : Color.white.opacity(0.5),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.18), radius: 24, y: 8)
            .scaleEffect(appeared ? 1.0 : 0.85)
            .opacity(appeared ? 1.0 : 0.0)
            .accessibilityIdentifier("reaction_picker")
        }
        // VoiceOver: the overlay is a plain ZStack layer, not a presentation,
        // so without `.isModal` VO focus escaped into the (blurred) feed
        // behind it; and the backdrop tap-to-dismiss is not a VO element, so
        // a VO user could only leave by POSTING a reaction. `.isModal` fences
        // focus to the picker; the escape action (two-finger Z) cancels —
        // sighted tap-outside dismissal is unchanged.
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) {
            dismiss()
        }
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }

    private func pill(emoji: String, index: Int, c: AppTheme.Colors) -> some View {
        let isMine = currentReaction == emoji
        return Button {
            Haptics.success()
            onPick(emoji)
            // Parent closes overlay — we just fade out.
            withAnimation(.easeOut(duration: 0.18)) {
                appeared = false
            }
        } label: {
            // Selected state: solid peach disc (Figma #FCE4DB — one of the
            // two allowed literals; adaptive accentDim in dark).
            Text(emoji)
                .font(.system(size: 26))
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(
                            isMine
                            ? (scheme == .dark
                               ? AppTheme.accentDim
                               : Color(red: 0xFC/255, green: 0xE4/255, blue: 0xDB/255))
                            : Color.clear
                        )
                )
                .scaleEffect(isMine ? 1.08 : 1.0)
        }
        .buttonStyle(.plain)
        // Staggered entry: emojis pop in sequentially.
        .offset(y: appeared ? 0 : 12)
        .animation(
            .spring(response: 0.32, dampingFraction: 0.6)
                .delay(Double(index) * 0.035),
            value: appeared
        )
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.18)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            onDismiss()
        }
    }
}
