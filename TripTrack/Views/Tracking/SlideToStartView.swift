import SwiftUI

/// Slide-to-start control on the idle Record screen. Earlier version was a
/// flat track with a single orange thumb and dimming hint text — correct
/// but unexciting. This revision layers three motion cues:
///
///  1. An ambient Ording-style shimmer sweeps across "Slide to start" every
///     1.8s, fading out as the user commits past 30% drag.
///  2. A "wake" of accent color fills the track behind the thumb as it
///     moves, so commitment accumulates visually.
///  3. A staggered chevron trail on the right of the thumb nudges the
///     direction of travel; it fades once the user has clearly begun the
///     gesture (progress > 0.15).
///
/// At threshold (85%) the thumb springs the last 15%, the play glyph morphs
/// into a checkmark, and the whole control fades + scales down so it feels
/// like the action was consumed rather than just snapping back — the
/// reveal of the recording HUD sells the transition.
struct SlideToStartView: View {
    let onStartTrip: () -> Void
    @EnvironmentObject private var lang: LanguageManager

    @State private var dragOffset: CGFloat = 0
    @State private var isCompleted = false
    @State private var halfHapticFired = false
    @State private var nearHapticFired = false

    private let thumbSize: CGFloat = 48
    private let trackHeight: CGFloat = 56
    private let cornerRadius: CGFloat = 16
    private let horizontalInset: CGFloat = 4
    private let threshold: CGFloat = 0.85

    var body: some View {
        GeometryReader { geo in
            let maxOffset = geo.size.width - thumbSize - horizontalInset * 2
            let progress = maxOffset > 0 ? min(dragOffset / maxOffset, 1.0) : 0

            ZStack(alignment: .leading) {
                trackBackground
                wakeFill(progress: progress, maxOffset: maxOffset)
                shimmerHint(progress: progress)
                chevronTrail(progress: progress)
                thumb(progress: progress, maxOffset: maxOffset)
            }
            .opacity(isCompleted ? 0 : 1)
            .scaleEffect(isCompleted ? 0.96 : 1)
            .animation(.easeOut(duration: 0.25), value: isCompleted)
        }
        .frame(height: trackHeight)
    }

    // MARK: - Layers

    private var trackBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(AppTheme.accent.opacity(0.15))
    }

    /// A second rounded rect clipped to the current drag width. The `+ thumbSize`
    /// extension is intentional — the wake fills up to (and behind) the thumb,
    /// so the thumb never exposes bare track behind itself.
    private func wakeFill(progress: CGFloat, maxOffset: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(AppTheme.accent.opacity(0.35))
            .frame(width: dragOffset + thumbSize + horizontalInset * 2)
            .allowsHitTesting(false)
    }

    /// Masked-gradient shimmer that sweeps L→R across the hint text on a
    /// 1.8s loop. Uses `TimelineView(.animation)` with a wrapping `phase`
    /// that the gradient reads to advance its `startPoint`/`endPoint`.
    /// Once the user starts actually dragging (progress > 0.3) the shimmer
    /// fades out — their attention has moved on.
    @ViewBuilder
    private func shimmerHint(progress: CGFloat) -> some View {
        let text = AppStrings.slideToStart(lang.language)
        let label = Text(text)
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity)

        let opacity = max(0, 1 - progress / 0.3)

        ZStack {
            // Base dim layer so the text is still legible before the
            // shimmer sweeps over it.
            label.foregroundStyle(.white.opacity(0.25))

            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = (t.truncatingRemainder(dividingBy: 1.8)) / 1.8
                label
                    .foregroundStyle(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0), location: max(0, phase - 0.2)),
                                .init(color: .white.opacity(0.85), location: phase),
                                .init(color: .white.opacity(0), location: min(1, phase + 0.2)),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
        .allowsHitTesting(false)
        .opacity(opacity)
    }

    /// Three small chevrons marching right, placed just inside the track
    /// ahead of the thumb. Staggered fade + x-offset loop. Disappear once
    /// the user has actually begun dragging.
    @ViewBuilder
    private func chevronTrail(progress: CGFloat) -> some View {
        let visible = max(0, 1 - progress / 0.15)
        if visible > 0 {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = (t.truncatingRemainder(dividingBy: 0.9)) / 0.9
                HStack(spacing: 2) {
                    chevron(delay: 0.0, phase: phase)
                    chevron(delay: 0.2, phase: phase)
                    chevron(delay: 0.4, phase: phase)
                }
                .padding(.leading, horizontalInset + thumbSize + 10 + dragOffset)
            }
            .opacity(visible)
            .allowsHitTesting(false)
        }
    }

    private func chevron(delay: Double, phase: Double) -> some View {
        let local = (phase + delay).truncatingRemainder(dividingBy: 1)
        // A small triangle pulse: bump in, fade out.
        let alpha: Double = {
            if local < 0.3 { return local / 0.3 * 0.7 }
            if local < 0.7 { return 0.7 - (local - 0.3) / 0.4 * 0.5 }
            return max(0, 0.2 - (local - 0.7) / 0.3 * 0.2)
        }()
        return Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(alpha))
    }

    private func thumb(progress: CGFloat, maxOffset: CGFloat) -> some View {
        Circle()
            .fill(AppTheme.accent)
            .frame(width: thumbSize, height: thumbSize)
            .overlay {
                Image(systemName: isCompleted ? "checkmark" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .shadow(color: AppTheme.accent.opacity(0.4), radius: 8)
            .offset(x: dragOffset + horizontalInset)
            .gesture(dragGesture(maxOffset: maxOffset))
    }

    // MARK: - Gesture

    private func dragGesture(maxOffset: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isCompleted else { return }
                let raw = value.translation.width
                // Rubber-band: past maxOffset, resistance compresses further
                // motion into a tiny visible overdrag (~8pt) using sqrt easing.
                let clamped: CGFloat
                if raw < 0 { clamped = 0 }
                else if raw <= maxOffset { clamped = raw }
                else { clamped = maxOffset + sqrt(raw - maxOffset) * 2 }
                dragOffset = clamped

                let progress = clamped / maxOffset
                if progress >= 0.5 && !halfHapticFired {
                    halfHapticFired = true
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                if progress >= 0.8 && !nearHapticFired {
                    nearHapticFired = true
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .onEnded { _ in
                guard !isCompleted else { return }
                let progress = dragOffset / maxOffset
                if progress >= threshold {
                    // Commit: snap to end, fire heavy haptic, invoke callback,
                    // then let the fade-out handle the dismissal. Parent view
                    // will unmount this when recording starts.
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        dragOffset = maxOffset
                    }
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    isCompleted = true
                    onStartTrip()
                    // Reset state in case the control stays mounted (e.g.
                    // recording failed to start). Delay longer than the fade
                    // so the user doesn't see the thumb rubber-band back.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                        isCompleted = false
                        halfHapticFired = false
                        nearHapticFired = false
                    }
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        dragOffset = 0
                    }
                    halfHapticFired = false
                    nearHapticFired = false
                }
            }
    }
}
