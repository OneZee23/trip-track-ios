import SwiftUI
import CoreLocation
import QuartzCore

/// Fullscreen «cinema» replay of an OWN trip (Figma 117:533, spec section C
/// «Реплей»): the poster route canvas full-bleed on #121214, the car riding
/// the timestamped track, a floating speed bubble, photo-moment strip and a
/// scrubbable transport bar with 1×/2×/4× rates.
///
/// Presented as a fullScreenCover from the «Прожить заново» CTA — only for
/// trips that carry per-point timestamps (the social «Смотреть поездку»
/// keeps its inline crawl; social DTOs ship no timestamps).
struct TripReplayView: View {
    let trip: Trip
    /// Downsampled (≤300) poster series — index-aligned, same arrays the
    /// detail poster feeds to PosterRouteCanvas.
    let coordinates: [CLLocationCoordinate2D]
    /// m/s, aligned with `coordinates`.
    let speeds: [Double]
    /// Aligned per-point timestamps — drive the time-true playback.
    let timestamps: [Date]

    @StateObject private var engine = TripReplayEngine()
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var themeManager: ThemeManager
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var storyShare: (data: StoryShareData, url: String?)?
    @State private var isGeneratingShare = false
    /// Playback was running when a scrub began — resume on release.
    @State private var resumeAfterScrub = false

    /// Root cinema background (Figma #121214).
    private static let rootBg = Color(red: 0x12/255, green: 0x12/255, blue: 0x14/255)
    private static let tileBg = Color(red: 0x23/255, green: 0x26/255, blue: 0x2E/255)

    private static let hhmmFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Photos in ride order for the moments strip.
    private var sortedPhotos: [TripPhoto] {
        trip.photos.sorted { $0.timestamp < $1.timestamp }
    }

    /// Wall-clock moment of the playback head, mapped over the track span.
    private var currentTripDate: Date {
        guard let t0 = timestamps.first, let tN = timestamps.last else { return trip.startDate }
        return t0.addingTimeInterval(tN.timeIntervalSince(t0) * engine.progress)
    }

    /// Photo the playhead has most recently passed (nearest ≤ head time).
    private var activePhotoId: UUID? {
        let now = currentTripDate
        return sortedPhotos.last(where: { $0.timestamp <= now })?.id
    }

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

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                PosterRouteCanvas(
                    coordinates: coordinates,
                    speeds: speeds,
                    playbackCoord: engine.headCoord,
                    playbackTrailIndex: engine.trailIndex,
                    style: .cinema
                )

                // Figma cinema gradient: rgba(18,18,20,.5) → 0@30% → 0@50%
                // → .94@100% — keeps the route readable mid-frame while the
                // chrome zones go near-black.
                LinearGradient(
                    stops: [
                        .init(color: Self.rootBg.opacity(0.5), location: 0),
                        .init(color: Self.rootBg.opacity(0), location: 0.30),
                        .init(color: Self.rootBg.opacity(0), location: 0.50),
                        .init(color: Self.rootBg.opacity(0.94), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                speedBubble(in: geo.size)

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 16)
                        .padding(.top, safeAreaTop + 6)

                    Spacer(minLength: 0)

                    bottomBlock
                        .padding(.horizontal, 16)
                        .padding(.bottom, safeAreaBottom + 8)
                }
            }
        }
        .background(Self.rootBg)
        .ignoresSafeArea()
        .task {
            engine.configure(
                coords: coordinates,
                timestamps: timestamps,
                speeds: speeds,
                distanceMeters: trip.distance
            )
            engine.play()
        }
        .onDisappear { engine.stop() }
        .sheet(isPresented: Binding(
            get: { storyShare != nil },
            set: { if !$0 { storyShare = nil } }
        )) {
            if let share = storyShare {
                StoryShareSheet(data: share.data, shareUrl: share.url)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .environmentObject(lang)
                    .preferredColorScheme(themeManager.preferredColorScheme)
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            PosterCircleButton(
                systemImage: "xmark",
                accessibilityLabelText: AppStrings.cancel(lang.language)
            ) { dismiss() }

            Spacer(minLength: 0)

            // «02:14 / 04:58» — trip-time elapsed / total, H:MM.
            Text("\(Self.hmm(engine.progress * trip.duration)) / \(Self.hmm(trip.duration))")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.black.opacity(0.32), in: Capsule())

            Spacer(minLength: 0)

            PosterCircleButton(
                systemImage: "square.and.arrow.up",
                accessibilityLabelText: AppStrings.share(lang.language)
            ) {
                engine.pause()
                Task { await openStoryShare() }
            }
            .disabled(isGeneratingShare)
        }
        .frame(height: 40)
    }

    // MARK: - Speed bubble

    /// Current-speed pill floating above the car, projected through the
    /// same equirectangular fit the canvas draws with, clamped inside the
    /// chrome-free band.
    @ViewBuilder
    private func speedBubble(in size: CGSize) -> some View {
        if speeds.count == coordinates.count, !speeds.isEmpty,
           let head = engine.headCoord,
           let pt = PosterRouteCanvas.overlayPoint(for: head, route: coordinates, in: size) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(engine.currentSpeedKmh.rounded()))")
                    .font(.system(size: 15, weight: .heavy).monospacedDigit())
                    .foregroundStyle(AppTheme.accent)
                Text(AppStrings.kmh(lang.language))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.black.opacity(0.32), in: Capsule())
            .position(
                x: min(max(pt.x, 62), size.width - 62),
                y: min(max(pt.y - 34, safeAreaTop + 66), size.height - safeAreaBottom - 190)
            )
            .allowsHitTesting(false)
            .animation(nil, value: engine.progress)
        }
    }

    // MARK: - Bottom block

    private var bottomBlock: some View {
        VStack(spacing: 14) {
            if !sortedPhotos.isEmpty {
                photoStrip
            }
            transportRow
        }
    }

    /// Photo moments — 62pt tiles with HH:mm under each; the tile the
    /// playhead has passed gets the white active border, tapping seeks.
    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(sortedPhotos) { photo in
                    photoMoment(photo)
                }
            }
            .padding(.horizontal, 14)
        }
        .scrollClipDisabled()
    }

    private func photoMoment(_ photo: TripPhoto) -> some View {
        let isActive = photo.id == activePhotoId
        return VStack(spacing: 4) {
            AsyncThumbnailView(filename: photo.filename, maxSize: 124)
                .frame(width: 62, height: 62)
                .background(Self.tileBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    if isActive {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white, lineWidth: 2)
                    }
                }
            Text(Self.hhmmFormatter.string(from: photo.timestamp))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(isActive ? 0.7 : 0.32))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.tap()
            seek(to: photo.timestamp)
        }
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }

    private var transportRow: some View {
        HStack(spacing: 14) {
            Button {
                Haptics.tap()
                engine.togglePlay()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain)

            progressBar

            Button {
                Haptics.selection()
                engine.cycleRate()
            } label: {
                Text("\(Int(engine.rate))×")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// h5 track + white fill + 13pt knob; the whole strip is a drag surface
    /// so scrubbing doesn't demand landing on the knob.
    private var progressBar: some View {
        GeometryReader { g in
            let w = max(g.size.width, 1)
            let x = CGFloat(engine.progress) * w
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(height: 5)
                Capsule()
                    .fill(.white)
                    .frame(width: max(x, 5), height: 5)
                Circle()
                    .fill(.white)
                    .frame(width: 13, height: 13)
                    .position(x: min(max(x, 6.5), w - 6.5), y: g.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Suspend the clock for the drag — otherwise the
                        // display link keeps advancing progress between
                        // touch events and the playhead runs away from a
                        // stationary finger.
                        if engine.isPlaying {
                            engine.pause()
                            resumeAfterScrub = true
                        }
                        engine.seek(to: Double(value.location.x / w))
                    }
                    .onEnded { _ in
                        if resumeAfterScrub {
                            resumeAfterScrub = false
                            // Released at the very end → hold the final
                            // frame (play() would restart from zero).
                            if engine.progress < 1 { engine.play() }
                        }
                    }
            )
        }
        .frame(height: 28)
    }

    // MARK: - Seek / share

    private func seek(to timestamp: Date) {
        guard let t0 = timestamps.first, let tN = timestamps.last else { return }
        let span = tN.timeIntervalSince(t0)
        guard span > 0 else { return }
        engine.seek(to: timestamp.timeIntervalSince(t0) / span)
    }

    /// Same share flow as the detail screen — StoryShareSheet is hosted
    /// HERE (a sheet can't present from the covered parent while this
    /// fullScreenCover is up).
    private func openStoryShare() async {
        guard !isGeneratingShare else { return }
        isGeneratingShare = true
        defer { isGeneratingShare = false }

        let authorName = AuthService.shared.userName
            ?? (lang.language == .ru ? "Моя поездка" : "My trip")
        let data = StoryShareData.from(
            trip, authorName: authorName,
            authorEmoji: settings.avatarEmoji, lang: lang.language)

        var url: String?
        if AuthService.shared.isSignedIn {
            do {
                let req = SocialShareRequest(tripId: trip.id, expiresInDays: nil)
                let res: SocialShareResponse = try await APIClient.shared.post(
                    APIEndpoint.socialShare, body: req)
                url = res.shareUrl
            } catch {
                url = nil
            }
        }
        storyShare = (data, url)
    }

    /// «02:14» — zero-padded H:MM of a trip-time interval.
    private static func hmm(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d", s / 3600, (s % 3600) / 60)
    }
}

// MARK: - Engine

/// Purpose-built playback clock for the replay screen. Sibling of
/// `RoutePlaybackController` (which stays untouched for the inline poster
/// crawl) with the extra transport the cinema UI needs: pause/resume,
/// scrub-seek, 1×/2×/4× rate, published progress and speed-at-head.
///
/// Follows the same CADisplayLink + O(1)-per-frame contract: the playhead
/// maps `progress` → trip time and walks a monotonic cursor through the
/// (≤300-point) timestamp array; seeks reset the cursor.
final class TripReplayEngine: NSObject, ObservableObject {
    /// Playback position 0…1 over the track's time span.
    @Published private(set) var progress: Double = 0
    @Published private(set) var isPlaying = false
    /// Interpolated car position for the current frame.
    @Published private(set) var headCoord: CLLocationCoordinate2D?
    /// Last passed original coordinate — feeds the canvas trail.
    @Published private(set) var trailIndex: Int = -1
    /// Interpolated speed at the head, km/h.
    @Published private(set) var currentSpeedKmh: Double = 0
    /// Playback rate multiplier (1 / 2 / 4).
    @Published private(set) var rate: Double = 1

    private var coords: [CLLocationCoordinate2D] = []
    private var timestamps: [Date] = []
    private var speeds: [Double] = []
    /// Real seconds for a full 1× run — same adaptive pacing as the inline
    /// controller (~1.4 s/km clamped to a watchable window).
    private var baseDuration: Double = 12
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    /// Monotonic segment cursor — reset on seeks/backward jumps.
    private var cursor = 0

    /// Seeds the series and renders frame 0 (car at the start dot).
    /// No-ops on malformed input (fewer than 2 points or misaligned
    /// timestamps) — the view simply shows the idle poster.
    func configure(
        coords: [CLLocationCoordinate2D],
        timestamps: [Date],
        speeds: [Double],
        distanceMeters: Double
    ) {
        guard coords.count >= 2, timestamps.count == coords.count else { return }
        self.coords = coords
        self.timestamps = timestamps
        self.speeds = speeds.count == coords.count ? speeds : []
        let km = max(0, distanceMeters / 1000.0)
        baseDuration = max(7.0, min(40.0, km * 1.4))
        progress = 0
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
        cursor = 0
    }

    /// 1× → 2× → 4× → 1×. Rate multiplies the per-tick advance, so
    /// changing it mid-flight is seamless (no clock re-anchor needed).
    func cycleRate() {
        rate = rate >= 4 ? 1 : rate * 2
    }

    /// Scrub/photo-tap seek — works both paused and playing.
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
    }
}
