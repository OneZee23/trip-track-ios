import Foundation
import Combine

/// Drives the "play back this route" animation. Owns a single Timer
/// that ticks at 30Hz for `totalSeconds`, publishing fractional
/// progress 0…1 → nil. Built as an ObservableObject (not view-local
/// `@State`) so:
///   - The instance survives view re-creation cycles and can be
///     `stop`-ed cleanly from `.onDisappear` — view-local `@State`
///     timers leak past dismissal.
///   - The 30Hz updates only invalidate consumers that read
///     `controller.progress`, not the full parent body.
///
/// Race-safety:
///   - `Timer(timeInterval:..., repeats:)` + `RunLoop.add(.common)` is
///     used instead of `Timer.scheduledTimer` because the latter adds
///     to `.default` mode and the `.common` add then double-enrolls,
///     causing 60Hz fire on a 30Hz schedule.
///   - `generation` counter guards the post-completion `Task.sleep`
///     so a quick stop+start within the 1.2s "hold" doesn't let the
///     stale completion clear the new run's progress.
final class RoutePlaybackController: ObservableObject {
    @Published private(set) var progress: Double? = nil

    private var timer: Timer?
    private var generation: Int = 0

    private let totalSeconds: Double = 8.0
    private let tickHz: Double = 30.0

    var isPlaying: Bool { progress != nil }

    func toggle() { isPlaying ? stop() : start() }

    func start() {
        stop()
        let myGen = generation
        var elapsed: Double = 0
        progress = 0
        let t = Timer(timeInterval: 1.0 / tickHz, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            elapsed += 1.0 / self.tickHz
            let p = min(1.0, elapsed / self.totalSeconds)
            self.progress = p
            if p >= 1.0 {
                timer.invalidate()
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(1200))
                    guard let self, self.generation == myGen else { return }
                    self.progress = nil
                    self.timer = nil
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }

    func stop() {
        generation &+= 1
        timer?.invalidate()
        timer = nil
        progress = nil
    }
}
