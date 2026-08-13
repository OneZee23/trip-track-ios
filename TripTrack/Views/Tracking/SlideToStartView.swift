import SwiftUI
import OSLog

private let slideLog = Logger(subsystem: "com.triptrack", category: "record-screen")

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
    /// Overrides the default «Сдвиньте» hint (e.g. «Открыть Настройки» on the
    /// geo-denied idle state, Figma 475:119).
    var labelOverride: String? = nil
    /// Held state: the control will not move and says what it is waiting for.
    ///
    /// Letting the thumb travel and then refusing at the end is the shape of
    /// the reported bug — the swipe looks like it worked, and the only thing
    /// that comes back is the thumb. A control that cannot act should not
    /// pretend to; it stays put and answers the moment you touch it.
    var isBlocked: Bool = false
    var blockedLabel: String? = nil
    /// Touched while blocked — the screen raises the explanation.
    var onBlockedAttempt: () -> Void = {}
    @EnvironmentObject private var lang: LanguageManager

    @State private var dragOffset: CGFloat = 0
    @State private var isCompleted = false
    @State private var halfHapticFired = false
    @State private var nearHapticFired = false
    @State private var blockedNotified = false

    // Figma draws the track 292×56 with a 48 thumb inside a 360 pt frame —
    // a 5.2:1 pill. Those numbers were copied literally, but the height is
    // fixed while the width follows the screen, so on a 440 pt phone the same
    // track stretches to 6.6:1 and reads thin and flat instead of the chunky
    // control the design has. Taller restores the proportion.
    private let thumbSize: CGFloat = 56
    private let trackHeight: CGFloat = 64
    // Figma 144:1163: the track is a full pill (radius 999).
    private let cornerRadius: CGFloat = 32
    private let horizontalInset: CGFloat = 4
    /// 0.85 asked for the whole track. On a 440 pt phone that is 260 pt of
    /// travel, and stopping a hair short threw the thumb home with nothing
    /// said — indistinguishable from the control being broken. Two thirds is
    /// still an unmistakably deliberate swipe, and it is roughly where
    /// slide-to-unlock style controls commit.
    private let threshold: CGFloat = 0.66

    var body: some View {
        GeometryReader { geo in
            let maxOffset = geo.size.width - thumbSize - horizontalInset * 2
            let progress = maxOffset > 0 ? min(dragOffset / maxOffset, 1.0) : 0

            ZStack(alignment: .leading) {
                trackBackground
                if !isBlocked {
                    wakeFill(progress: progress, maxOffset: maxOffset)
                    shimmerHint(progress: progress)
                    chevronTrail(progress: progress)
                } else {
                    blockedHint
                }
                thumb(progress: progress, maxOffset: maxOffset)
            }
            .opacity(isCompleted ? 0 : 1)
            .scaleEffect(isCompleted ? 0.96 : 1)
            .animation(.easeOut(duration: 0.25), value: isCompleted)
            .animation(.easeInOut(duration: 0.25), value: isBlocked)
            // Touching a held control has to answer immediately, wherever on
            // the track the finger lands — not only on the thumb.
            .contentShape(Rectangle())
            .gesture(blockedTapGesture, including: isBlocked ? .all : .none)
        }
        .frame(height: trackHeight)
        // VoiceOver / Switch Control can't perform a drag gesture, and this
        // control is the ONLY way to start a trip (or open Settings in the
        // geo-denied state). Represent it as a plain button: activation
        // (double-tap) runs the same completion path as a full slide.
        .accessibilityRepresentation {
            if isBlocked {
                Button(blockedLabel ?? AppStrings.slideWaitingForGPS(lang.language)) {
                    onBlockedAttempt()
                }
            } else {
                Button(labelOverride ?? AppStrings.slideToStart(lang.language)) {
                    completeSlide()
                }
            }
        }
        .accessibilityIdentifier("slide_to_start")
    }

    // MARK: - Layers

    private var trackBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(isBlocked ? Color.white.opacity(0.07) : AppTheme.accent.opacity(0.15))
    }

    /// What the control is waiting for, stated on the control. No shimmer and
    /// no chevrons — both of those say «drag me», and it will not be dragged.
    private var blockedHint: some View {
        Text(blockedLabel ?? AppStrings.slideWaitingForGPS(lang.language))
            .font(.inter(17, weight: .semibold))
            .foregroundStyle(.white.opacity(0.5))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.leading, thumbSize + 24)
            .padding(.trailing, 16)
            .allowsHitTesting(false)
    }

    /// Any touch on a held control raises the explanation once per touch.
    private var blockedTapGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !blockedNotified else { return }
                blockedNotified = true
                onBlockedAttempt()
            }
            .onEnded { _ in blockedNotified = false }
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
        let text = labelOverride ?? AppStrings.slideToStart(lang.language)
        let label = Text(text)
            .font(.inter(17, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            // Centered on the FULL pill (Figma) — the 6.1.0 hints are short
            // («Сдвиньте»/«Slide»), so they no longer collide with the thumb.
            // The geo-denied override is not short, though: «Открыть
            // Настройки» ran straight under the marching chevrons. Reserving
            // the thumb's lane keeps the centred look for the short labels and
            // pushes the long one clear.
            .frame(maxWidth: .infinity)
            .padding(.leading, isLongLabel(text) ? thumbSize + 44 : 16)
            .padding(.trailing, 16)

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

    /// «Сдвиньте» / «Slide» clear the chevrons on their own; anything the
    /// length of «Открыть Настройки» does not. Counting characters is crude
    /// but it is measuring the only thing that matters here and needs no
    /// layout pass to do it.
    private func isLongLabel(_ text: String) -> Bool { text.count > 12 }

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
            .fill(isBlocked ? Color(white: 0.32) : AppTheme.accent)
            .frame(width: thumbSize, height: thumbSize)
            .overlay {
                if isBlocked {
                    // A spinner is the literal truth: something is still
                    // happening, and it is not your turn yet.
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white.opacity(0.8))
                } else {
                    Image(systemName: isCompleted ? "checkmark" : "play.fill")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .shadow(color: isBlocked ? .clear : AppTheme.accent.opacity(0.4), radius: 8)
            .offset(x: (isBlocked ? 0 : dragOffset) + horizontalInset)
            .gesture(dragGesture(maxOffset: maxOffset), including: isBlocked ? .none : .all)
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
                slideLog.notice("slide ended progress=\(progress, privacy: .public) threshold=\(threshold, privacy: .public) maxOffset=\(maxOffset, privacy: .public)")
                if progress >= threshold {
                    // Commit: snap to end, then run the shared completion path.
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        dragOffset = maxOffset
                    }
                    completeSlide()
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        dragOffset = 0
                    }
                    halfHapticFired = false
                    nearHapticFired = false
                }
            }
    }

    /// Shared completion: heavy haptic, fade-out, callback. Reached either by
    /// a full drag past the threshold or by an accessibility activation.
    private func completeSlide() {
        guard !isCompleted else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        isCompleted = true
        // NOT in the same breath as the line above.
        //
        // `isCompleted` is @State, so setting it opens a SwiftUI update pass.
        // Calling `onStartTrip()` synchronously right after published the
        // view model's `isRecording` change from INSIDE that pass, and SwiftUI
        // drops what it is given mid-update: the recording genuinely started —
        // GPS switched to recording mode, points were being saved — while the
        // screen kept showing the idle card with a live slider. Sliding again
        // then stopped the trip nobody could see had begun.
        //
        // Handing the call to the next runloop turn lets this update finish
        // first, so the publish lands where a subscriber can hear it.
        DispatchQueue.main.async { onStartTrip() }
        // The control stays mounted when the start was refused, so the thumb
        // has to come home — but that return is the ONLY thing a refused user
        // sees, and on its own it reads as the slider failing. The screen
        // raises a toast saying why; this just gets out of its way.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                dragOffset = 0
            }
            isCompleted = false
            halfHapticFired = false
            nearHapticFired = false
        }
    }
}
