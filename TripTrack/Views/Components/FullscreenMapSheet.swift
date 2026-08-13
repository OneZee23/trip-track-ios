import SwiftUI
import MapKit
import QuartzCore

/// Full-screen, interactive route viewer presented from both TripDetailView
/// and SocialTripDetailView — and, when the track carries per-point
/// timestamps, the replay itself.
///
/// The replay used to be a screen of its own (`TripReplayView`): the same
/// route, on the same real map, one level deeper than the map you had just
/// opened. Two full-screen surfaces showing the same thing is one too many,
/// so the cinema moved in here — you open the map, press play, and watch the
/// drive on the map you were already looking at.
///
/// Chrome per Figma 117:1803: a close circle top-left and a «+» / «−» pair on
/// the right edge. The playback chrome joins that stack only when there is
/// something to play.
///
/// The bottom used to also carry a full-width key explaining what the route's
/// colours meant. It is gone: it took a band of every screen to restate a
/// legend, and the route's own colours already run from green to red in front
/// of you.
struct FullscreenMapSheet: View {
    let coordinates: [CLLocationCoordinate2D]
    /// m/s, aligned with `coordinates` — paints the route and sets the top
    /// end of the speed plaque's scale.
    var speeds: [Double] = []
    /// Per-point timestamps, aligned with `coordinates`. Their presence is
    /// what turns this sheet into the replay: a social preview polyline ships
    /// none, and without them there is no clock to play a drive against.
    /// Per-point times for the replay. May be a DOWNSAMPLED series — see
    /// `replayCoordinates`.
    var timestamps: [Date] = []
    /// Coordinates the replay walks, when the caller has a cheaper series
    /// than the one the route is drawn from. The trail overlay is rebuilt
    /// every time the head passes a waypoint, so a raw ten-hour track makes
    /// that tens of thousands of rebuilds of an ever-longer polyline. The
    /// route itself is still drawn from `coordinates`, at full resolution.
    var replayCoordinates: [CLLocationCoordinate2D] = []
    /// m/s aligned with `replayCoordinates` — what the car's speed readout is
    /// interpolated from. Separate from `speeds` for the same reason the
    /// coordinates are: those paint the route at full resolution, these walk
    /// the downsampled series, and the two counts do not match. Feeding the
    /// engine the route's copy is what pinned the readout at «0 км/ч» — the
    /// count check rejected it and left the engine with no speeds at all.
    var replaySpeeds: [Double] = []
    /// The trip's own distance in metres — the second half of the replay
    /// readout. 0 (the default, and every call site without timestamps)
    /// simply drops that half.
    var distanceMeters: Double = 0
    /// Whose drive this is — the play control says «Прожить заново» on your
    /// own and «Смотреть» on someone else's.
    var isOwnTrip: Bool = true
    var fogCutoffDate: Date?
    /// Forwarded to the map — someone else's trip carries no fog of mine.
    var showsFog: Bool = true
    /// Social trips pass `true` — their preview polyline is sparsely sampled
    /// and the gap-splitting in RouteMapView would zero out the bounds.
    var treatAsPreview: Bool = false
    /// Used for the speed plaque's "km/h" unit and the replay readout. Default
    /// keeps the social call site (speeds empty → no plaque) unchanged.
    var language: LanguageManager.Language = .en

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    /// Bumped by the zoom buttons; the map reads the change, not the value.
    @State private var zoomTick = 0
    @StateObject private var engine = TripReplayEngine()
    /// Fallback playback for a route with no per-point times.
    ///
    /// A trip that arrived over sync carries only a preview polyline, so
    /// there is nothing to play in REAL time — but «watch this trip» should
    /// still mean something. This is the paced crawl the trip detail used to
    /// offer for exactly those trips; when the port moved replay in here it
    /// took the timestamped half only, and synced trips silently lost the
    /// ability to be watched at all.
    @StateObject private var crawl = RoutePlaybackController()
    /// Camera rides with the car instead of framing the whole route.
    ///
    /// OFF to start with, unlike the old replay screen. There the map was not
    /// interactive, so riding with the car was the only way to see a street;
    /// here you arrived by panning and zooming a map yourself, and grabbing
    /// the camera the instant you press play would throw away the framing you
    /// just chose. The toggle is one tap away when you want the ride.
    @State private var followsCar = false
    /// Playback was running when a scrub began — resume on release.
    @State private var resumeAfterScrub = false

    /// Whether this route can be replayed at all.
    ///
    /// Timestamps decide, and they have to line up with the coordinates:
    /// the engine no-ops on a misaligned series, so chrome gated on the count
    /// alone would offer a play button that does nothing.
    /// The series the replay actually walks — the caller's cheap one when it
    /// gave us one, otherwise the drawn route.
    private var playbackSeries: [CLLocationCoordinate2D] {
        replayCoordinates.isEmpty ? coordinates : replayCoordinates
    }

    private var canReplay: Bool {
        playbackSeries.count > 1 && timestamps.count > 1
            && timestamps.count == playbackSeries.count
    }

    /// No usable times, but a route worth watching — the crawl's case.
    private var canCrawl: Bool { !canReplay && playbackSeries.count > 1 }

    private var isPlaying: Bool { canReplay ? engine.isPlaying : crawl.isPlaying }

    var body: some View {
        ZStack {
            RouteMapView(
                coordinates: coordinates,
                speeds: speeds,
                isInteractive: true,
                fogCutoffDate: fogCutoffDate,
                showsFog: showsFog,
                treatAsPreview: treatAsPreview,
                zoomTick: zoomTick,
                // The car and its trail are RouteMapView's job already — the
                // replay only has to say where the head is this frame.
                playbackCarCoord: canReplay ? engine.headCoord : crawl.currentCoord,
                playbackTrailIndex: canReplay ? engine.trailIndex : crawl.currentTrailIndex,
                playbackCoords: (canReplay || canCrawl) ? playbackSeries : nil,
                playbackFollow: followsCar,
                fitInsets: (canReplay || canCrawl) ? replayFitInsets : nil
            )
            .ignoresSafeArea()

            // Pinned to the MAP's centre, not the chrome's: the map ignores
            // the safe area, so the two centres are ~12pt apart and the bubble
            // would sit visibly off the car.
            speedBubble
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .ignoresSafeArea()
                .offset(y: -46)
                .allowsHitTesting(false)

            // The chrome deliberately does NOT ignore the safe area, so every
            // control lands inside it instead of being nudged there by hand.
            // Layout follows what every map app has taught people: the way out
            // is top-left and the zoom is thumb-height on the right.
            //
            // The replay controls slot into the two gaps that layout leaves
            // rather than on top of anything: the timecode takes the empty
            // middle of the top bar (where it is also furthest from both
            // thumbs — it is a readout, not a target) with the camera toggle
            // filling the unused top-right corner, and the transport bar
            // becomes a full-width plaque along the bottom. Everything down
            // there is one VStack, so the transport can never land under the
            // zoom column — it pushes it, it does not overlap it.
            VStack(spacing: 0) {
                HStack {
                    mapCircleButton(
                        systemImage: "xmark",
                        label: AppStrings.closeSheet(language),
                        identifier: "fullscreen_map_close"
                    ) {
                        dismiss()
                    }
                    Spacer(minLength: 0)
                    // Riding with the car has nothing to do with WHICH kind of
                    // playback is running — the car moves either way. Gating
                    // this on the timestamped one made someone else's trip a
                    // visibly poorer screen than your own for no reason the
                    // viewer could see.
                    if canReplay || canCrawl { cameraToggle }
                }
                // The timecode has to read as centred on the bar, and between
                // two Spacers it would not be: the camera toggle makes the
                // right side a whole button wider than the left. An overlay
                // puts it on the bar's true centre whatever flanks it.
                .overlay(alignment: .center) {
                    if canReplay { timecodePill }
                }

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    Spacer(minLength: 0)
                    zoomControls
                }

                if canReplay || canCrawl {
                    transportPlaque
                        .padding(.top, 12)
                }

            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            // Clears the «Apple Maps · Legal» strip along the bottom edge,
            // which Apple requires to stay visible and which the speed key was
            // sitting directly on top of.
            .padding(.bottom, 36)
        }
        .task {
            // Seeded, not started: the sheet opens as a map — the drive plays
            // when you ask for it. Seeding still parks the car on the start
            // dot, which is what advertises that there is a drive to watch.
            guard canReplay else { return }
            engine.configure(
                coords: playbackSeries,
                timestamps: timestamps,
                speeds: replaySpeeds.count == playbackSeries.count ? replaySpeeds : []
            )
        }
        .onDisappear {
            engine.stop()
            crawl.stop()
        }
    }

    // MARK: - Replay chrome

    /// Framing padding for the whole-route fit, replay only.
    ///
    /// Left `nil` the map keeps its stock 30pt fit — that is today's
    /// fullscreen map and it must not move. With the transport plaque and the
    /// speed key stacked along the bottom, that same fit would tuck the last
    /// kilometres of the route under the chrome, so a replay asks for a bottom
    /// margin the size of what actually sits there.
    private var replayFitInsets: UIEdgeInsets {
        UIEdgeInsets(
            // 190, not 160: the chrome stack (transport plaque + speed key +
            // its bottom padding) reaches ~192pt off the screen bottom, and
            // the map puts Apple's legal strip at this margin. At 160 the
            // strip landed INSIDE the blurred plaque and was unreadable —
            // which is not a thing we are allowed to do to it.
            top: safeAreaTop + 56, left: 28,
            bottom: safeAreaBottom + 190, right: 28
        )
    }

    /// The insets go to a UIKit map that ignores the safe area, so the numbers
    /// have to be looked up rather than laid out.
    private var safeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 47
    }

    private var safeAreaBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 34
    }

    /// A button says what it will DO, not what is already true.
    ///
    /// The glyph used to name the current state — the arrow while the camera
    /// was already following, the map while it already showed the whole route
    /// — which is exactly backwards for a control: following the car, you were
    /// offered a «follow the car» arrow. Its spoken label had it right all
    /// along («Показать весь маршрут» while following), so the two contradicted
    /// each other; the glyph is what moved.
    private var cameraToggle: some View {
        mapCircleButton(
            systemImage: followsCar ? "map" : "location.fill",
            label: language == .ru
                ? (followsCar ? "Показать весь маршрут" : "Следовать за машиной")
                : (followsCar ? "Show whole route" : "Follow the car"),
            identifier: "replay_camera_toggle"
        ) {
            withAnimation(.easeInOut(duration: 0.25)) { followsCar.toggle() }
        }
    }

    /// «02:14 / 04:58 · 12,4 км» — how far into the drive the playhead is, in
    /// both units a drive is measured in.
    ///
    /// The total is the TRACK's own span rather than the trip's stored
    /// duration: what plays back is the track, and a readout counting towards
    /// a total the playhead can never reach lies by however much the two
    /// differ.
    private var timecodePill: some View {
        let c = AppTheme.colors(for: scheme)
        return Text(readoutText)
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(c.text)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(c.border, lineWidth: 1))
            // Purely a readout — it must never swallow a tap meant for the
            // buttons it now sits between.
            .allowsHitTesting(false)
    }

    private var readoutText: String {
        let elapsed = Self.hmm(engine.progress * trackDuration)
        let total = Self.hmm(trackDuration)
        guard distanceMeters > 0 else { return "\(elapsed) / \(total)" }
        let km = distanceMeters * engine.distanceFraction / 1000
        let covered = GarageFormat.oneDecimal(km, isRu: language == .ru)
        return "\(elapsed) / \(total) · \(covered) \(AppStrings.km(language))"
    }

    private var trackDuration: TimeInterval {
        guard let first = timestamps.first, let last = timestamps.last else { return 0 }
        return max(0, last.timeIntervalSince(first))
    }

    /// Live speed, riding just above the car.
    ///
    /// Only while the camera follows: MapKit then holds the car at the map's
    /// own centre, so the bubble can sit above that centre with no projection
    /// maths at all. Pulled back to the whole route the car's screen position
    /// belongs to MapKit and nobody else, and a bubble parked in a corner
    /// labels nothing — there the coloured route and the key along the bottom
    /// already answer "how fast was I going here".
    @ViewBuilder
    private var speedBubble: some View {
        if canReplay, followsCar, engine.headCoord != nil, engine.hasSpeeds {
            let c = AppTheme.colors(for: scheme)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(engine.currentSpeedKmh.rounded()))")
                    .font(.system(size: 15, weight: .heavy).monospacedDigit())
                    .foregroundStyle(AppTheme.accent)
                Text(AppStrings.kmh(language))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(c.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(c.border, lineWidth: 1))
        }
    }

    /// Play / scrub / rate as one plaque, cut to the same width and corner as
    /// the speed key below it so the bottom of the screen reads as one object
    /// with two rows rather than a control bar someone dropped on a legend.
    /// The crawl cannot be seeked and has no timecode to seek TO, so it gets a
    /// line that fills rather than a scrubber and a rate control — two controls
    /// that could not answer what they ask. It does get the line: a lone button
    /// in a full-width plaque read as a bar that had failed to load.
    private var transportPlaque: some View {
        HStack(spacing: 12) {
            playButton
            if canReplay {
                progressBar
                rateButton
            } else {
                crawlProgressBar
            }
            if hasStarted { stopButton }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassBackground(cornerRadius: 16)
    }

    /// Carries the role the detail screen's «Прожить заново» pill used to
    /// have — that button is gone, this is where reliving a trip starts now.
    private var playButton: some View {
        Button {
            Haptics.tap()
            if canReplay {
                engine.togglePlay()
            } else {
                crawl.toggle(
                    coords: playbackSeries,
                    timestamps: nil,
                    distanceMeters: distanceMeters
                )
            }
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 44, height: 44)
                .background(Circle().fill(AppTheme.accent.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // «Смотреть» on someone else's trip: you cannot relive a drive that
        // was not yours. `watchTrip` lost its only call site when the detail's
        // replay pill was deleted — this is where that distinction lives now.
        .accessibilityLabel(isPlaying
            ? AppStrings.stop(language)
            : (isOwnTrip ? AppStrings.reliveTrip(language) : AppStrings.watchTrip(language)))
        .accessibilityIdentifier("fullscreen_replay_play")
    }

    /// The playback has been begun and left something on the map — a car, a
    /// trail, a camera that followed. Only then is there anything to clear.
    private var hasStarted: Bool {
        canReplay
            ? (engine.isPlaying || engine.progress > 0 || engine.headCoord != nil)
            : (crawl.isPlaying || crawl.progress > 0)
    }

    /// Puts the map back the way it was found: no car, no trail, whole route
    /// in frame. Pausing leaves the drive parked on top of the route, which is
    /// no way to go back to just looking at where you went.
    private var stopButton: some View {
        let c = AppTheme.colors(for: scheme)
        return Button {
            Haptics.tap()
            withAnimation(.easeInOut(duration: 0.25)) { followsCar = false }
            engine.stop()
            crawl.stop()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(c.textSecondary)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language == .ru ? "Убрать воспроизведение" : "Clear playback")
        .accessibilityIdentifier("fullscreen_replay_stop")
    }

    private var rateButton: some View {
        let c = AppTheme.colors(for: scheme)
        return Button {
            Haptics.selection()
            engine.cycleRate()
        } label: {
            Text(Self.rateLabel(engine.rate))
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(c.textSecondary)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("fullscreen_replay_rate")
    }

    /// How far the crawl has got, and nothing more: no knob, because there is
    /// nothing to grab — a trip that arrived over sync has no per-point times,
    /// so there is no position to seek to. Showing the same knob would promise
    /// a scrub that cannot happen.
    private var crawlProgressBar: some View {
        let c = AppTheme.colors(for: scheme)
        return GeometryReader { g in
            let w = max(g.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(c.textTertiary.opacity(0.35))
                    .frame(height: 5)
                Capsule()
                    .fill(AppTheme.accent)
                    .frame(width: max(CGFloat(crawl.progress) * w, 0), height: 5)
            }
            .frame(height: g.size.height, alignment: .center)
        }
        .frame(height: 40)
        .animation(.linear(duration: 0.1), value: crawl.progress)
        .accessibilityIdentifier("fullscreen_crawl_progress")
    }

    /// 5pt track + accent fill + 13pt knob; the whole strip is a drag surface
    /// so scrubbing doesn't demand landing on the knob.
    private var progressBar: some View {
        let c = AppTheme.colors(for: scheme)
        return GeometryReader { g in
            let w = max(g.size.width, 1)
            let x = CGFloat(engine.progress) * w
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(c.textTertiary.opacity(0.35))
                    .frame(height: 5)
                Capsule()
                    .fill(AppTheme.accent)
                    .frame(width: max(x, 5), height: 5)
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 13, height: 13)
                    .position(x: min(max(x, 6.5), w - 6.5), y: g.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Suspend the clock for the drag — otherwise the
                        // display link keeps advancing progress between touch
                        // events and the playhead runs away from a stationary
                        // finger.
                        if engine.isPlaying {
                            engine.pause()
                            resumeAfterScrub = true
                        }
                        engine.seek(to: Double(value.location.x / w))
                    }
                    .onEnded { _ in
                        if resumeAfterScrub {
                            resumeAfterScrub = false
                            // Released at the very end → hold the final frame
                            // (play() would restart from zero).
                            if engine.progress < 1 { engine.play() }
                        }
                    }
            )
        }
        .frame(height: 28)
    }

    /// «1×», «1,5×», «5×». Whole rates lose the decimal, and the separator
    /// follows the device locale — a Russian phone writes 1,5.
    private static func rateLabel(_ rate: Double) -> String {
        let number = rateFormatter.string(from: NSNumber(value: rate))
            ?? String(format: "%g", rate)
        return "\(number)×"
    }

    private static let rateFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f
    }()

    /// «02:14» — zero-padded H:MM of a trip-time interval.
    private static func hmm(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d", s / 3600, (s % 3600) / 60)
    }

    // MARK: - Zoom

    /// «+» / «−» as one grouped control — pinch is not the only way people zoom
    /// a map, and it is a poor one when the other hand is holding a phone.
    private var zoomControls: some View {
        let c = AppTheme.colors(for: scheme)
        return VStack(spacing: 0) {
            zoomButton(systemImage: "plus", label: language == .ru ? "Приблизить" : "Zoom in") {
                zoomTick += 1
            }
            Rectangle()
                .fill(c.textTertiary.opacity(0.25))
                .frame(width: 26, height: 1)
            zoomButton(systemImage: "minus", label: language == .ru ? "Отдалить" : "Zoom out") {
                zoomTick -= 1
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(c.card)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        )
    }

    private func zoomButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        let c = AppTheme.colors(for: scheme)
        return Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(c.text)
                .frame(width: 44, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("fullscreen_map_\(systemImage)")
    }

    private func mapCircleButton(
        systemImage: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        let c = AppTheme.colors(for: scheme)
        return Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(c.text)
                .frame(width: 40, height: 40)
                .background(Circle().fill(c.card))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Engine

/// Playback clock for the replay. Sibling of `RoutePlaybackController` (which
/// stays untouched for the inline poster crawl) with the transport the replay
/// needs: pause/resume, scrub-seek, a rate ladder, published progress and
/// speed-at-head.
///
/// It moved here with the replay itself, from the screen that used to host it.
///
/// Follows the same CADisplayLink + O(1)-per-frame contract: the playhead maps
/// `progress` → trip time and walks a monotonic cursor through the (≤300-point)
/// timestamp array; seeks reset the cursor.
final class TripReplayEngine: NSObject, ObservableObject {
    /// Playback position 0…1 over the track's time span.
    @Published private(set) var progress: Double = 0
    @Published private(set) var isPlaying = false
    /// Interpolated car position for the current frame.
    @Published private(set) var headCoord: CLLocationCoordinate2D?
    /// Last passed original coordinate — feeds the map's trail.
    @Published private(set) var trailIndex: Int = -1
    /// Interpolated speed at the head, km/h.
    @Published private(set) var currentSpeedKmh: Double = 0
    /// Whether this playback carries speeds at all — the readout is hidden
    /// rather than parked at zero when it does not.
    var hasSpeeds: Bool { !speeds.isEmpty }
    /// Fraction of the route's LENGTH the head has covered, 0…1.
    ///
    /// Separate from `progress` on purpose: time and distance are not the same
    /// story. Twenty minutes at a level crossing move the clock and not the
    /// odometer, so a covered-kilometres readout scaled off the clock would
    /// invent distance the drive never made.
    @Published private(set) var distanceFraction: Double = 0
    /// Playback rate multiplier. 1× is real time — the car covers the road at
    /// the speed it was actually driven.
    @Published private(set) var rate: Double = 1

    /// The ladder the rate button walks. Starts at truth and climbs from there;
    /// the old 1/2/4 ladder started at "watchable" and never offered truth at
    /// all, which made every drive look like a getaway.
    static let rateLadder: [Double] = [1, 1.5, 2, 3, 5]

    private var coords: [CLLocationCoordinate2D] = []
    private var timestamps: [Date] = []
    private var speeds: [Double] = []
    /// Metres from the start at each coordinate — built once per configure, so
    /// the distance readout costs one lerp per frame instead of a walk.
    private var cumulativeMetres: [Double] = []
    /// Wall-clock seconds for a full 1× run. This is the trip's OWN duration,
    /// so at 1× the playback and the drive take the same time and the car
    /// moves across the map at the speed it really moved. The previous value
    /// was an adaptive 7–40 s window, which squeezed a two-hour drive into
    /// half a minute and made the car tear along the road at an impossible
    /// pace — the whole point of reliving a trip is that it looks like the
    /// trip.
    private var baseDuration: Double = 12
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    /// Monotonic segment cursor — reset on seeks/backward jumps.
    private var cursor = 0

    /// Seeds the series and renders frame 0 (car at the start dot).
    /// No-ops on malformed input (fewer than 2 points or misaligned
    /// timestamps) — the map simply shows the route and no car.
    func configure(
        coords: [CLLocationCoordinate2D],
        timestamps: [Date],
        speeds: [Double]
    ) {
        guard coords.count >= 2, timestamps.count == coords.count else { return }
        self.coords = coords
        self.timestamps = timestamps
        self.speeds = speeds.count == coords.count ? speeds : []
        var running: [Double] = [0]
        running.reserveCapacity(coords.count)
        for i in 1..<coords.count {
            running.append(running[i - 1] + GeometryUtils.haversineDistance(coords[i - 1], coords[i]))
        }
        cumulativeMetres = running
        // The track's own span. A floor keeps a degenerate track (all points
        // stamped the same second) from dividing by zero and jumping straight
        // to the end.
        let span = timestamps[timestamps.count - 1].timeIntervalSince(timestamps[0])
        baseDuration = max(1, span)
        rate = 1
        progress = 0
        distanceFraction = 0
        cursor = 0
        applyFrame()
    }

    func play() {
        guard coords.count >= 2, displayLink == nil else { return }
        // Replaying from the end restarts the ride.
        if progress >= 1 {
            progress = 0
            cursor = 0
            applyFrame()
        }
        isPlaying = true
        lastTick = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func pause() {
        displayLink?.invalidate()
        displayLink = nil
        isPlaying = false
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func stop() {
        pause()
        headCoord = nil
        trailIndex = -1
        progress = 0
        distanceFraction = 0
        cursor = 0
    }

    /// Walks the ladder and wraps. Rate multiplies the per-tick advance, so
    /// changing it mid-flight is seamless (no clock re-anchor needed).
    func cycleRate() {
        let ladder = Self.rateLadder
        let next = ladder.firstIndex(of: rate).map { ($0 + 1) % ladder.count } ?? 0
        rate = ladder[next]
    }

    /// Scrub seek — works both paused and playing.
    func seek(to p: Double) {
        guard coords.count >= 2 else { return }
        progress = min(max(p, 0), 1)
        cursor = 0
        applyFrame()
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        // Clamp: CADisplayLink is suspended in background while the media
        // clock keeps running — an unclamped dt after re-foregrounding
        // would jump the playhead to the end in one frame.
        let dt = min(now - lastTick, 0.5)
        lastTick = now
        progress = min(1, progress + dt * rate / baseDuration)
        applyFrame()
        if progress >= 1 {
            // Hold the final frame — the play button restarts from zero.
            pause()
        }
    }

    private func applyFrame() {
        guard coords.count >= 2 else { return }
        let t0 = timestamps[0]
        let span = timestamps[timestamps.count - 1].timeIntervalSince(t0)
        guard span > 0 else {
            // Degenerate span (all-same timestamps) — park at the end.
            headCoord = coords[coords.count - 1]
            trailIndex = coords.count - 1
            distanceFraction = 1
            return
        }
        let target = t0.addingTimeInterval(span * progress)
        if cursor > 0, timestamps[cursor] > target { cursor = 0 }
        while cursor + 1 < timestamps.count, timestamps[cursor + 1] <= target {
            cursor += 1
        }
        let lo = cursor
        let hi = min(lo + 1, coords.count - 1)
        let segDur = timestamps[hi].timeIntervalSince(timestamps[lo])
        let frac = segDur > 0
            ? min(1, max(0, target.timeIntervalSince(timestamps[lo]) / segDur))
            : 0
        headCoord = CLLocationCoordinate2D(
            latitude: coords[lo].latitude + (coords[hi].latitude - coords[lo].latitude) * frac,
            longitude: coords[lo].longitude + (coords[hi].longitude - coords[lo].longitude) * frac
        )
        trailIndex = lo
        if !speeds.isEmpty {
            let s = speeds[lo] + (speeds[hi] - speeds[lo]) * frac
            currentSpeedKmh = max(0, s * 3.6)
        }
        if cumulativeMetres.count == coords.count, let total = cumulativeMetres.last, total > 0 {
            let covered = cumulativeMetres[lo] + (cumulativeMetres[hi] - cumulativeMetres[lo]) * frac
            distanceFraction = min(1, max(0, covered / total))
        }
    }
}
