import SwiftUI
import MapKit

struct TrackingView: View {
    @EnvironmentObject var viewModel: MapViewModel
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var settings = SettingsManager.shared
    @State private var safeAreaTop: CGFloat = 59
    @State private var tabBarHeight: CGFloat = 88
    @State private var isMapReady = false

    var body: some View {
        ZStack {
            // Map is ALWAYS instantiated so "ready" can never hang on a missed
            // async hop. The loader overlay sits on top until the map's first
            // render (onMapReady) or the timeout fallback in `.task` below.
            MapViewRepresentable(
                userTrackingMode: $viewModel.userTrackingMode,
                overlays: viewModel.trackOverlays,
                isDarkMap: viewModel.isDarkMap,
                bottomInset: viewModel.isRecording ? 0 : idleHUDInset,
                zoomDelta: $viewModel.zoomDelta,
                isRecording: viewModel.isRecording,
                onCameraDistanceChanged: { viewModel.currentCameraDistance = $0 },
                onVisibleRectChanged: { viewModel.handleVisibleRectChange($0) },
                onFogRendererCreated: { viewModel.fogRenderer = $0 },
                onMapReady: {
                    if !isMapReady {
                        withAnimation(.easeOut(duration: 0.4)) { isMapReady = true }
                    }
                }
            )
            .ignoresSafeArea()
            .allowsHitTesting(!viewModel.isRecording)
            .modifier(PixelateModifier(active: viewModel.isRecording, scale: 3.0))

            // Loading overlay until the map reports its first render. Never
            // swallows taps on the slide-to-start control beneath it.
            if !isMapReady {
                CarLoadingView()
                    .allowsHitTesting(false)
            }

            // `accessibilityHidden` keeps the opacity-hidden overlay out of
            // the a11y tree — VoiceOver (and UI tests) otherwise still see
            // the invisible controls.
            recordingOverlay
                .opacity(viewModel.isRecording ? 1 : 0)
                .allowsHitTesting(viewModel.isRecording)
                .accessibilityHidden(!viewModel.isRecording)

            idleOverlay
                .opacity(viewModel.isRecording ? 0 : 1)
                .allowsHitTesting(!viewModel.isRecording)
                .accessibilityHidden(viewModel.isRecording)

            // Shared top bar — always same position. Left slot: back chevron
            // while idle (the tab bar is hidden on this tab, the chevron is
            // the only way out), REC/ПАУЗА status pill while recording
            // (Figma 146:1178 / 477:119 have no back affordance).
            VStack(spacing: 10) {
                HStack {
                    if viewModel.isRecording {
                        recordingStatusPill
                    } else {
                        backButton
                    }
                    Spacer()
                    if !(viewModel.locationDenied && !viewModel.isRecording) {
                        GPSIndicatorView(
                            accuracy: viewModel.gpsAccuracy,
                            isStale: viewModel.isRecording && viewModel.gpsSignalStale
                        )
                    }
                }

                if viewModel.isRecording && viewModel.isPaused {
                    pausedPill
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Signal-state banners are suppressed while paused — the
                // paused pill already explains why nothing is moving, and
                // signal loss is expected in a parking garage.
                if viewModel.isRecording && !viewModel.isPaused && viewModel.gpsSignalStale {
                    signalLostBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if viewModel.isRecording && !viewModel.isPaused
                            && viewModel.gpsAccuracy > 35 {
                    weakSignalToast
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, safeAreaTop + 4)
            .animation(.easeInOut(duration: 0.25), value: viewModel.isPaused)
            .animation(.easeInOut(duration: 0.25), value: viewModel.gpsSignalStale)
            .ignoresSafeArea(edges: .top)
        }
        .animation(.easeInOut(duration: 0.5), value: viewModel.isRecording)
        .onAppear {
            viewModel.refreshTripStats()
            viewModel.requestLocationPermission()
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = scene.windows.first {
                safeAreaTop = window.safeAreaInsets.top
                tabBarHeight = 54 + window.safeAreaInsets.bottom
            }
        }
        .task {
            // Hard fallback so the loader can NEVER outlive ~0.6s even if the
            // map's render callback is delayed (offline tiles, contended cold
            // start). The old fire-and-forget onAppear Task could be starved on
            // a busy launch and leave the spinner stuck forever — the reported
            // "Готов к поездке" infinite-loading hang.
            try? await Task.sleep(for: .milliseconds(600))
            if !isMapReady {
                withAnimation(.easeOut(duration: 0.4)) { isMapReady = true }
            }
        }
        .onDisappear {
            if !viewModel.isRecording {
                viewModel.stopLocationUpdates()
            }
        }
        // The trip summary sheet is presented from ContentView's root —
        // «Завершить и сохранить» in the recovery prompt can finish a trip
        // while ANY tab is active, and this view only exists on .record.
    }

    // MARK: - Recording Overlay (Figma 146:1178 — everything lives at the bottom)

    private var recordingOverlay: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 14) {
                // Speedometer — 92pt fixed accent (grey while paused/lost).
                VStack(spacing: 0) {
                    Text(speedText)
                        .font(.system(size: 92, weight: .heavy))
                        .kerning(-3.68)
                        .foregroundStyle(speedDimmed ? AppTheme.textTertiary : AppTheme.accent)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: speedText)
                    Text(AppStrings.kmh(lang.language).uppercased())
                        .font(.system(size: 13, weight: .medium))
                        .kerning(0.78)
                        .foregroundStyle(.white.opacity(0.55))
                }

                // Metrics glass panel: distance | time | altitude.
                HStack(spacing: 0) {
                    statItem(
                        value: String(format: "%.1f", viewModel.distance),
                        unit: AppStrings.km(lang.language),
                        icon: "point.topleft.down.curvedto.point.bottomright.up"
                    )
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 1, height: 40)
                    statItem(
                        value: viewModel.duration,
                        unit: nil,
                        icon: "clock"
                    )
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 1, height: 40)
                    statItem(
                        value: "\(Int(viewModel.altitude))",
                        unit: AppStrings.m(lang.language),
                        icon: "mountain.2"
                    )
                }
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color(red: 40/255, green: 40/255, blue: 42/255).opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )

                controlsRow
            }
            .padding(.horizontal, 16)
            .padding(.bottom, safeAreaBottom + 12)

        }
        .ignoresSafeArea(edges: [.top, .bottom])
    }

    /// Pause circle (52pt, white 15%; accent resume while paused) + wide red
    /// Stop bar (Figma 146:1178 / 477:119).
    private var controlsRow: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.togglePause()
            } label: {
                Image(systemName: viewModel.isPaused ? "playpause.fill" : "pause.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(
                        viewModel.isPaused ? AppTheme.accent : Color.white.opacity(0.15),
                        in: Circle()
                    )
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tracking_pause")

            Button {
                Haptics.success()
                viewModel.toggleRecording()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 19, weight: .bold))
                    Text(AppStrings.stop(lang.language))
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(AppTheme.red, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tracking_stop")
        }
    }

    // MARK: - Recording status pills / banners (Figma 146:1178, 477:119, 435:119, 494:119)

    /// «REC · 00:34:12» red dot / «ПАУЗА · 00:34:12» amber dot, glass pill.
    private var recordingStatusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.isPaused
                      ? Color(red: 0xFF/255, green: 0x9F/255, blue: 0x0A/255)
                      : Color(red: 0xFF/255, green: 0x45/255, blue: 0x3A/255))
                .frame(width: 8, height: 8)
            Text("\(viewModel.isPaused ? AppStrings.pauseShort(lang.language) : "REC") · \(viewModel.duration)")
                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(red: 40/255, green: 40/255, blue: 42/255).opacity(0.72)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }

    /// Centered amber «Запись на паузе» pill.
    private var pausedPill: some View {
        let amber = Color(red: 0xFF/255, green: 0x9F/255, blue: 0x0A/255)
        return HStack(spacing: 7) {
            Image(systemName: "pause.fill")
                .font(.system(size: 11, weight: .bold))
            Text(AppStrings.recordingPausedPill(lang.language))
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(amber)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Capsule().fill(amber.opacity(0.16)))
    }

    /// Red toast: sustained weak accuracy (>35м) while recording.
    private var weakSignalToast: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(red: 0xFF/255, green: 0x45/255, blue: 0x3A/255))
                .frame(width: 22, height: 22)
                .overlay(
                    Text("!")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(AppStrings.weakSignalTitle(lang.language))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(AppStrings.weakSignalHint(lang.language))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(red: 0xB8/255, green: 0xB8/255, blue: 0xC2/255))
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 41/255, green: 20/255, blue: 18/255).opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(red: 0xFF/255, green: 0x45/255, blue: 0x3A/255).opacity(0.35), lineWidth: 1)
        )
    }

    /// Amber banner: GPS fix lost mid-trip (Kalman keeps the track alive).
    private var signalLostBanner: some View {
        let amber = Color(red: 0xF5/255, green: 0xA6/255, blue: 0x23/255)
        return HStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(amber)
            VStack(alignment: .leading, spacing: 1) {
                Text(AppStrings.signalLostTitle(lang.language))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(AppStrings.signalLostHint(lang.language))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(red: 0xC9/255, green: 0xA8/255, blue: 0x78/255))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 42/255, green: 31/255, blue: 18/255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(amber.opacity(0.4), lineWidth: 1)
        )
    }

    /// «0» grey while paused, «–» while the signal is lost, live speed
    /// otherwise (en-dash: a 92pt em-dash reads as a redacted slab).
    private var speedText: String {
        if viewModel.isPaused { return "0" }
        if viewModel.gpsSignalStale { return "–" }
        return "\(Int(viewModel.speed))"
    }

    private var speedDimmed: Bool {
        viewModel.isPaused || viewModel.gpsSignalStale
    }

    /// Figma metrics cell: dimmed 13pt icon ABOVE the value row, centered.
    private func statItem(value: String, unit: String?, icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.4))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .heavy).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit.uppercased())
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Back Button (idle only)

    private var backButton: some View {
        Button {
            NotificationCenter.default.post(name: .switchToFeedTab, object: nil)
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.4), in: Circle())
        }
        .accessibilityIdentifier("tracking_back")
    }

    // MARK: - Idle Overlay

    private var idleOverlay: some View {
        VStack(spacing: 0) {
            // Space for shared top bar
            Color.clear
                .frame(height: safeAreaTop + 52)

            Spacer()

            // Map controls — right side
            HStack {
                Spacer()
                mapControls
                    .padding(.trailing, 16)
                    .padding(.bottom, 12)
            }

            // Idle HUD — flush to bottom edge
            IdleHUDView(
                totalKm: viewModel.cachedTotalKm,
                tripCount: viewModel.cachedTripCount,
                locationDenied: viewModel.locationDenied,
                onStartTrip: { viewModel.toggleRecording() }
            )
            .padding(.bottom, 8)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Map Controls (location on top, then +, then -)

    private var mapControls: some View {
        VStack(spacing: 8) {
            mapButton(icon: trackingIcon, color: trackingIconColor, enabled: true) {
                viewModel.cycleTrackingMode()
            }
            mapButton(icon: "plus", color: nil, enabled: viewModel.canZoomIn) {
                viewModel.zoomIn()
            }
            mapButton(icon: "minus", color: nil, enabled: viewModel.canZoomOut) {
                viewModel.zoomOut()
            }
        }
    }

    @ViewBuilder
    private func mapButton(icon: String, color: Color?, enabled: Bool, action: @escaping () -> Void) -> some View {
        let isDark = viewModel.isDarkMap
        let fg = color ?? (enabled ? (isDark ? .white : AppTheme.textPrimary) : (isDark ? Color.white.opacity(0.3) : AppTheme.textPrimary.opacity(0.3)))

        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(fg)
                .frame(width: 44, height: 44)
                .background {
                    if isDark {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(white: 0.2).opacity(0.85))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.3), lineWidth: 1))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    }
                }
        }
        .disabled(!enabled)
    }

    // MARK: - Helpers

    private var trackingIcon: String {
        switch viewModel.userTrackingMode {
        case .none: return "location"
        case .follow: return "location.fill"
        case .followWithHeading: return "location.north.line.fill"
        @unknown default: return "location"
        }
    }

    private var trackingIconColor: Color {
        viewModel.userTrackingMode == .none ? AppTheme.textPrimary : AppTheme.accent
    }

    private var safeAreaBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 34
    }

    private var idleHUDInset: CGFloat {
        tabBarHeight + 380
    }
}

// MARK: - Pixel Art Effect

private struct PixelateModifier: ViewModifier {
    let active: Bool
    let scale: CGFloat

    func body(content: Content) -> some View {
        if active {
            content
                .compositingGroup()
                .scaleEffect(1.0 / scale, anchor: .center)
                .compositingGroup()
                .scaleEffect(scale, anchor: .center)
        } else {
            content
        }
    }
}

#Preview {
    TrackingView()
        .environmentObject(MapViewModel())
        .preferredColorScheme(.dark)
}
