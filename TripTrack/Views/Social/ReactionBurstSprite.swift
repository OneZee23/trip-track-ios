import SwiftUI

/// Tiny floating-emoji effect that fires when a reaction goes from
/// off → on. Animates a copy of the emoji upward + outward, scaling
/// up while fading out, over ~0.7s. Pure presentational; the parent
/// owns the lifetime via `Set<String>` membership and removes the
/// view when the animation finishes.
///
/// Why a separate view instead of inline modifiers: the burst sprite
/// needs its own `@State` for the animation phase, and putting that
/// `@State` on a per-pill view ensures each tap restarts the
/// animation from zero (`.onAppear` is the kickoff). Inline
/// `withAnimation` blocks would interfere with the parent pill's
/// own scale spring.
struct ReactionBurstSprite: View {
    let emoji: String
    @State private var phase: Double = 0

    var body: some View {
        Text(emoji)
            .font(.system(size: 30))
            .scaleEffect(0.6 + phase * 0.9)   // 0.6 → 1.5
            .opacity(1.0 - phase)              // 1.0 → 0
            .offset(y: -phase * 36)            // floats up 36pt
            .onAppear {
                withAnimation(.easeOut(duration: 0.7)) {
                    phase = 1.0
                }
            }
    }
}
