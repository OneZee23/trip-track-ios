import SwiftUI

/// Bottom undo toast (canon «note · тост undo»).
///
/// Rules it implements, verbatim from the design note:
/// - 10-second window, a ring timer counting 10 → 0 (the ring melts around
///   the circle);
/// - swipe DOWN closes the toast at once and the action STANDS;
/// - «Отменить» rolls the action back and the trip returns to its place;
/// - after 10 seconds the toast leaves on its own — and only then does the
///   real, irreversible work happen on the server.
///
/// That last rule is why the host defers the mutation instead of undoing it:
/// nothing is deleted or hidden server-side until this toast is gone.
struct UndoToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    /// Called when the window closes untouched — the real mutation.
    var onCommit: () -> Void
    /// Called on «Отменить» — put everything back.
    var onUndo: () -> Void

    static func == (lhs: UndoToast, rhs: UndoToast) -> Bool { lhs.id == rhs.id }
}

struct UndoToastView: View {
    let toast: UndoToast
    let undoLabel: String
    /// Seconds in the window. Canon: 10.
    var duration: TimeInterval = 10
    /// Toast is going away — the host decides commit vs undo before calling.
    let onClose: () -> Void

    @State private var remaining: TimeInterval
    @State private var ticker: Task<Void, Never>?

    init(
        toast: UndoToast,
        undoLabel: String,
        duration: TimeInterval = 10,
        onClose: @escaping () -> Void
    ) {
        self.toast = toast
        self.undoLabel = undoLabel
        self.duration = duration
        self.onClose = onClose
        _remaining = State(initialValue: duration)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.message)
                .font(.inter(14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                Haptics.action()
                toast.onUndo()
                onClose()
            } label: {
                HStack(spacing: 8) {
                    Text(undoLabel)
                        .font(.inter(14, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                    countdownRing
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
        // Swipe DOWN dismisses and KEEPS the action (canon). Undo is the
        // button; the gesture is the "I'm sure, get out of my way" path.
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    guard value.translation.height > 12 else { return }
                    toast.onCommit()
                    onClose()
                }
        )
        .onAppear { startTicking() }
        .onDisappear { ticker?.cancel() }
    }

    /// Accent ring that melts away as the window closes, with the seconds
    /// left inside it — the same countdown, read two ways.
    private var countdownRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0, remaining / duration))
                .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: remaining)
            Text("\(Int(ceil(remaining)))")
                .font(.inter(11, weight: .bold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: 26, height: 26)
    }

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { @MainActor in
            let step: TimeInterval = 0.2
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
                if Task.isCancelled { return }
                remaining = max(0, remaining - step)
            }
            // Window expired untouched — this is where the real work happens.
            toast.onCommit()
            onClose()
        }
    }
}
