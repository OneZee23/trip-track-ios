import SwiftUI

/// iMessage/Telegram-style reaction picker: blurred backdrop + floating
/// capsule with the 5 available emoji. Presented as a full-screen overlay
/// when the user long-presses a trip card.
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

            // Floating capsule with 5 emojis
            HStack(spacing: 6) {
                ForEach(Array(ReactionEmoji.all.enumerated()), id: \.offset) { index, emoji in
                    pill(emoji: emoji, index: index, c: c)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(scheme == .dark ? Color(white: 0.16) : Color.white)
                    .shadow(color: Color.black.opacity(0.25), radius: 24, y: 8)
            )
            .scaleEffect(appeared ? 1.0 : 0.85)
            .opacity(appeared ? 1.0 : 0.0)
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
            Text(emoji)
                .font(.system(size: 30))
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(isMine ? AppTheme.accentBg : Color.clear)
                )
                .overlay(
                    Circle()
                        .stroke(isMine ? AppTheme.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
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
