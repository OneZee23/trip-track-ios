import SwiftUI

/// Bottom undo toast (canon «note · тост undo»).
///
/// Rules it implements, verbatim from the design note:
/// - 10-second window, a ring timer counting 10 → 0 (the ring melts around
///   the circle);
/// - swipe DOWN closes the toast at once and the action STANDS;
/// - «Отменить» rolls the action back and the trip returns to its place;
/// - after 10 seconds the toast leaves on its own — and only then does the
///   real, irreversible work happen.
///
/// The window itself lives in `UndoActionCenter`, NOT here: a view that owns
/// the timer loses the pending write the moment SwiftUI tears it down (tab
/// switch, push, re-render). This view only draws the countdown and forwards
/// the two gestures.
struct UndoToastView: View {
    let pending: UndoActionCenter.Pending
    let undoLabel: String

    @ObservedObject private var center = UndoActionCenter.shared

    init(pending: UndoActionCenter.Pending, undoLabel: String) {
        self.pending = pending
        self.undoLabel = undoLabel
    }

    var body: some View {
        // TimelineView drives the ring off the shared deadline, so the
        // countdown stays truthful even if this view was created late.
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let remaining = max(0, pending.deadline.timeIntervalSince(context.date))
            content(remaining: remaining)
        }
    }

    private func content(remaining: TimeInterval) -> some View {
        HStack(spacing: 12) {
            Text(pending.message)
                .font(.inter(14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                Haptics.action()
                center.undo()
            } label: {
                HStack(spacing: 8) {
                    Text(undoLabel)
                        .font(.inter(14, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                    countdownRing(remaining: remaining)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .background(
            Capsule().fill(Color(red: 0x1B/255, green: 0x1B/255, blue: 0x1F/255))
        )
        .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
        .padding(.horizontal, 16)
        // Swipe DOWN dismisses and KEEPS the action (canon): the toast goes,
        // the work commits right away instead of waiting out the window.
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    guard value.translation.height > 12 else { return }
                    center.commitNow()
                }
        )
    }

    /// Accent ring that melts away as the window closes, with the seconds
    /// left inside it — the same countdown, read two ways.
    private func countdownRing(remaining: TimeInterval) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0, remaining / UndoActionCenter.window))
                .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(ceil(remaining)))")
                .font(.inter(11, weight: .bold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: 26, height: 26)
    }
}
