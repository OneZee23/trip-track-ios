import Foundation
import CoreLocation
import QuartzCore
import Combine

/// Pre-resampled, frame-paced route playback.
///
/// Key design points (informed by research into MapKit-native smooth
/// animation patterns — Strava / Polarsteps / Komoot follow the same
/// structure):
///
///   * **CADisplayLink, not Timer.** Timer fires at quasi-random offsets
///     relative to v-sync (0–16ms drift), so even with perfect
///     interpolation the screen shows stutters and double-frames.
///     CADisplayLink is frame-synced — it's what UIKit / Core Animation
///     use themselves. `preferredFrameRateRange` gives ProMotion 120Hz
///     while older devices fall back cleanly to 60Hz.
///
///   * **Pre-resample on start, not per-frame search.** For a 21-minute
///     trip compressed into 8 seconds the previous binary-search
///     approach found a different bracketing pair every frame, but
///     the *frame-to-frame deltas* were still large (~5 seconds of
///     trip time per frame), producing visible "teleport" between GPS
///     points. The fix is to pre-compute an evenly-time-spaced array
///     of (lat, lon) once at start. Per-frame cost is then an O(1)
///     array lookup.
///
///   * **Adaptive duration: ~1 s/km, clamped 5..30 s.** Fixed 8s is the
///     wrong default — a 200km trip in 8s plays as a 25 km/s blur, a
///     2km trip in 8s feels glacial. Scaling with distance keeps the
///     per-frame jump small for long trips (which is what causes the
///     jerkiness most users report).
///
///   * **Trail update gated on integer index.** Replacing the polyline
///     overlay every frame is the #1 source of MapKit frame drops.
///     `currentTrailIndex` only changes when the playback head passes
///     a real GPS waypoint; the map view checks for changes before
///     swapping the overlay.
final class RoutePlaybackController: NSObject, ObservableObject {
    @Published private(set) var isPlaying: Bool = false
    /// Interpolated car position for the current frame. nil = not playing.
    @Published private(set) var currentCoord: CLLocationCoordinate2D? = nil
    /// Index of the last *original* GPS coordinate the playback head has
    /// passed. Used by the map view to decide whether to redraw the
    /// trail polyline. -1 = trail not yet rendered.
    @Published private(set) var currentTrailIndex: Int = -1
    /// 0…1 through the crawl. Published so the transport bar can show a
    /// progress line: without one the bar was a lone play button in an
    /// otherwise empty plaque, which reads as something that failed to load
    /// rather than as a playback with no clock.
    @Published private(set) var progress: Double = 0

    private var displayLink: CADisplayLink?

    /// Pre-resampled (lat, lon) per frame. Index by frame number.
    private var resampled: [CLLocationCoordinate2D] = []
    /// Trail-head index per frame — points back at the last passed
    /// original GPS coord so the map view's growing polyline can keep
    /// pace without recomputing.
    private var trailHead: [Int] = []
    private var startedAt: CFTimeInterval = 0
    private var durationSeconds: Double = 0
    /// Race guard for the post-completion 1.2s hold. A quick stop+start
    /// within the hold window must not let the stale Task clear the
    /// new run's state.
    private var generation: Int = 0

    /// Pivot helper for the play/stop button.
    func toggle(coords: [CLLocationCoordinate2D], timestamps: [Date]?, distanceMeters: Double) {
        if isPlaying {
            stop()
        } else {
            start(coords: coords, timestamps: timestamps, distanceMeters: distanceMeters)
        }
    }

    func start(coords: [CLLocationCoordinate2D], timestamps: [Date]?, distanceMeters: Double) {
        stop()
        guard coords.count >= 2 else { return }

        // ~1.4s per km, clamped to a watchable window. Slower than the
        // first cut — the original 1s/km gave a "you can barely see the
        // car move on a long trip" effect. 1.4× pacing reads as
        // confident playback while still finishing in well under a
        // minute even for cross-country trips.
        let km = max(0, distanceMeters / 1000.0)
        durationSeconds = max(7.0, min(40.0, km * 1.4))

        // Resample to 60 frames/sec of playback duration. Even if the
        // display link runs at 120Hz, we read the same resampled point
        // (because `progress` indexes the precomputed array). That's
        // fine: at 120Hz the *animation* runs at 120Hz; only the
        // resolution of position lookup is capped at 60. The eye can't
        // tell the difference.
        let targetFps: Double = 60.0
        let totalFrames = max(60, Int(durationSeconds * targetFps))
        let useTime = timestamps?.count == coords.count

        resampled.removeAll(keepingCapacity: false)
        trailHead.removeAll(keepingCapacity: false)
        resampled.reserveCapacity(totalFrames)
        trailHead.reserveCapacity(totalFrames)

        // Linear walk through `timestamps` — they are monotonic, so a
        // running cursor (`searchStart`) replaces O(log n) binary
        // search per frame with O(1) amortised.
        var searchStart = 0
        let denom = Double(max(totalFrames - 1, 1))
        for f in 0..<totalFrames {
            let progress = Double(f) / denom
            let lo: Int
            let frac: Double
            if useTime, let ts = timestamps {
                let total = ts[ts.count - 1].timeIntervalSince(ts[0])
                if total <= 0 {
                    lo = coords.count - 1
                    frac = 0
                } else {
                    let target = ts[0].addingTimeInterval(total * progress)
                    while searchStart + 1 < ts.count && ts[searchStart + 1] <= target {
                        searchStart += 1
                    }
                    lo = searchStart
                    let hi = min(lo + 1, ts.count - 1)
                    let segDur = ts[hi].timeIntervalSince(ts[lo])
                    frac = segDur > 0 ? target.timeIntervalSince(ts[lo]) / segDur : 0
                }
            } else {
                // No timestamps available — fall back to linear-by-index.
                // Plays at constant on-screen speed; loses the
                // "lingers in traffic" feel but stays smooth.
                let exact = progress * Double(coords.count - 1)
                lo = max(0, min(coords.count - 2, Int(exact)))
                frac = exact - Double(lo)
            }
            let hi = min(lo + 1, coords.count - 1)
            let lat = coords[lo].latitude + (coords[hi].latitude - coords[lo].latitude) * frac
            let lon = coords[lo].longitude + (coords[hi].longitude - coords[lo].longitude) * frac
            resampled.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            trailHead.append(lo)
        }

        // Seed the published state so the first frame doesn't render
        // an empty car/trail.
        currentCoord = resampled[0]
        currentTrailIndex = trailHead[0]
        isPlaying = true
        startedAt = CACurrentMediaTime()

        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let elapsed = CACurrentMediaTime() - startedAt
        let progress = elapsed / durationSeconds
        if progress >= 1.0 {
            // Animation finished — hold the final frame for 1.2s before
            // clearing, so the user sees the completed trail before it
            // disappears.
            link.invalidate()
            displayLink = nil
            currentCoord = resampled.last
            currentTrailIndex = trailHead.last ?? -1
            self.progress = 1
            let myGen = generation
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(1200))
                guard let self, self.generation == myGen else { return }
                self.currentCoord = nil
                self.currentTrailIndex = -1
                self.isPlaying = false
                self.progress = 0
                self.resampled.removeAll(keepingCapacity: false)
                self.trailHead.removeAll(keepingCapacity: false)
            }
            return
        }
        let idx = min(resampled.count - 1, max(0, Int(progress * Double(resampled.count))))
        currentCoord = resampled[idx]
        currentTrailIndex = trailHead[idx]
        self.progress = progress
    }

    func stop() {
        generation &+= 1
        displayLink?.invalidate()
        displayLink = nil
        resampled.removeAll(keepingCapacity: false)
        trailHead.removeAll(keepingCapacity: false)
        currentCoord = nil
        currentTrailIndex = -1
        isPlaying = false
        progress = 0
    }
}
