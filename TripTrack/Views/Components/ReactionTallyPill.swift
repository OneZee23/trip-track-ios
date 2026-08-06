import SwiftUI

/// Interactive reaction pill (Figma ReactionPills 114:141): drawn icon +
/// count in a capsule.
///
/// It owns the *feel* of toggling, and the two directions are deliberately
/// asymmetric so taking your reaction back reads as an undo rather than as
/// casting another vote:
/// - landing  → crisp rigid click, the pill overshoots and springs back,
///   the icon morphs outline → filled accent, the count rolls up;
/// - removing → muted soft thud, the pill dips inward and settles, the icon
///   fades back to outline, the count rolls down.
struct ReactionTallyPill: View {
    let emoji: String
    let count: Int
    let isMine: Bool
    /// Owners can't react to their own trip (Strava rule) — the pill still
    /// renders, it just doesn't respond or fire feedback.
    var isEnabled: Bool = true
    var onTap: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Button {
            guard isEnabled else { return }
            if isMine { Haptics.reactionOff() } else { Haptics.reactionOn() }
            onTap()
        } label: {
            HStack(spacing: 4) {
                ReactionIconView(
                    emoji: emoji,
                    size: 14,
                    filled: isMine,
                    tint: isMine ? AppTheme.accent : c.text
                )
                Text("\(count)")
                    .font(.inter(12, weight: .bold).monospacedDigit())
                    .foregroundStyle(isMine ? AppTheme.accent : c.textSecondary)
                    // Digits roll in the direction of the change: up as the
                    // reaction lands, down as it's taken back.
                    .contentTransition(.numericText(countsDown: !isMine))
                    .animation(.snappy(duration: 0.26), value: count)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(isMine ? AppTheme.orangeDim : c.cardAlt))
            .overlay(Capsule().stroke(isMine ? AppTheme.accent : .clear, lineWidth: 1.5))
            .animation(.easeOut(duration: 0.22), value: isMine)
        }
        .buttonStyle(.plain)
        // Keyframes rather than a plain spring: the overshoot/dip has to
        // resolve back to 1.0 on its own, and the branch is evaluated when
        // the trigger fires, so each direction gets its own curve.
        .keyframeAnimator(initialValue: CGFloat(1), trigger: isMine) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(isMine ? 1.16 : 0.88, duration: 0.13, spring: .snappy)
                SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
            }
        }
    }
}
