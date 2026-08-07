import SwiftUI
import Combine

/// Owns the 10-second undo window and, crucially, the work that happens when
/// it closes.
///
/// The first cut ran the timer inside the toast view. That looked fine and
/// silently lost writes: SwiftUI tears the view down on a tab switch, a push,
/// or any feed re-render, `onDisappear` cancelled the timer, and the deferred
/// action — «сделать приватной», «удалить» — never ran. The card was gone
/// from the feed while the trip stayed public on the server, which is exactly
/// how a sign-out could still count two public trips after one had been
/// hidden.
///
/// So the window lives here, outside the view tree, and commits on three
/// paths: the timer expiring, the app leaving the foreground, and anything
/// asking for a new undoable action.
@MainActor
final class UndoActionCenter: ObservableObject {
    static let shared = UndoActionCenter()

    struct Pending: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let deadline: Date
        let commit: () -> Void
        let undo: () -> Void

        static func == (lhs: Pending, rhs: Pending) -> Bool { lhs.id == rhs.id }
    }

    /// Canon: ten seconds.
    static let window: TimeInterval = 10

    @Published private(set) var pending: Pending?

    private var timer: Task<Void, Never>?
    private var lifecycle: AnyCancellable?

    private init() {
        // Leaving the foreground closes the window immediately: a user who
        // swipes the app away must not lose the delete they just confirmed.
        lifecycle = NotificationCenter.default
            .publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.commitNow() }
            }
    }

    /// Register an action whose visible effect already happened optimistically
    /// and whose real work should run when the window closes.
    func schedule(message: String, commit: @escaping () -> Void, undo: @escaping () -> Void) {
        // One at a time: a second confirmation commits the first rather than
        // leaving it hanging with no toast to represent it.
        commitNow()
        let item = Pending(
            message: message,
            deadline: Date().addingTimeInterval(Self.window),
            commit: commit,
            undo: undo
        )
        pending = item
        timer = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.window * 1_000_000_000))
            guard !Task.isCancelled, let self, self.pending?.id == item.id else { return }
            self.commitNow()
        }
    }

    /// Window closed untouched (or the app is going away) — do the real work.
    func commitNow() {
        timer?.cancel()
        timer = nil
        guard let item = pending else { return }
        pending = nil
        item.commit()
    }

    /// «Отменить» — the action never happens; the caller puts the UI back.
    func undo() {
        timer?.cancel()
        timer = nil
        guard let item = pending else { return }
        pending = nil
        item.undo()
    }
}
