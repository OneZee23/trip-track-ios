import SwiftUI
import MapKit

struct TrackingView: View {
    @EnvironmentObject var viewModel: MapViewModel
    @EnvironmentObject private var lang: LanguageManager
    @State private var safeAreaTop: CGFloat = 59
    @State private var tabBarHeight: CGFloat = 88
    @State private var isMapReady = false

    var body: some View {
        ZStack {
            if isMapReady {
                // Full-screen MKMapView — deferred until loader is shown
                MapViewRepresentable(
                    userTrackingMode: $viewModel.userTrackingMode,
                    overlays: viewModel.trackOverlays,
                    isDarkMap: viewModel.isDarkMap,
                    bottomInset: viewModel.isRecording ? 0 : idleHUDInset,
                    zoomDelta: $viewModel.zoomDelta,
                    isRecording: viewModel.isRecording,
                    onCameraDistanceChanged: { viewModel.currentCameraDistance = $0 },
                    onVisibleRectChanged: { viewModel.handleVisibleRectChange($0) }
                )
                .ignoresSafeArea()
                .allowsHitTesting(!viewModel.isRecording)
                .modifier(PixelateModifier(active: viewModel.isRecording, scale: 3.0))
            }

            // Loading overlay while map initializes
            if !isMapReady {
                CarLoadingView()
            }

            recordingOverlay
                .opacity(viewModel.isRecording ? 1 : 0)
                .allowsHitTesting(viewModel.isRecording)

            idleOverlay
                .opacity(viewModel.isRecording ? 0 : 1)
                .allowsHitTesting(!viewModel.isRecording)

            // Shared top bar — always same position
            VStack {
                HStack {
                    backButton
                    Spacer()
                    GPSIndicatorView(accuracy: viewModel.gpsAccuracy)
                }
                .padding(.horizontal, 16)
                .padding(.top, safeAreaTop + 4)
                Spacer()
            }
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
            // Show loader first, then create the map
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.easeOut(duration: 0.4)) {
                    isMapReady = true
                }
            }
        }
        .onDisappear {
            if !viewModel.isRecording {
                viewModel.stopLocationUpdates()
            }
        }
        .sheet(item: $viewModel.lastCompletedTrip) { trip in
            TripCompleteSummaryView(
                trip: trip,
                completionData: viewModel.lastCompletionData,
                onPhotoSaved: { image in
                    _ = viewModel.tripManager.addPhoto(to: trip.id, image: image)
                },
                onDone: { dismissSummary() }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled()
        }
    }

    // MARK: - Recording Overlay

    private var recordingOverlay: some View {
        VStack(spacing: 0) {
            // Stats panel — compact, fixed height
            VStack(spacing: 12) {
                // Space for shared top bar
                Color.clear.frame(height: 44)

                // Speed — large
                VStack(spacing: 2) {
                    Text("\(Int(viewModel.speed))")
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundStyle(speedColor)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: Int(viewModel.speed))
                    Text("km/h")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }

                // Stats row: distance | time | altitude
                HStack(spacing: 0) {
                    statItem(
                        value: String(format: "%.1f", viewModel.distance),
                        unit: "km",
                        icon: "arrow.right"
                    )
                    Divider()
                        .frame(height: 28)
                        .background(.white.opacity(0.2))
                    statItem(
                        value: viewModel.duration,
                        unit: nil,
                        icon: "clock"
                    )
                    Divider()
                        .frame(height: 28)
                        .background(.white.opacity(0.2))
                    statItem(
                        value: "\(Int(viewModel.altitude))",
                        unit: "m",
                        icon: "mountain.2"
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, safeAreaTop + 4)
            .padding(.bottom, 16)
            .background(Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.85))
            .background(.ultraThinMaterial)

            // Mini-map takes remaining space (visible behind via ZStack)
            Spacer()

            // Controls: stop (center) + pause (left)
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 20) {
                    // Pause — small circle
                    Button {
                        viewModel.togglePause()
                    } label: {
                        Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(viewModel.isPaused ? .black : .white)
                            .frame(width: 48, height: 48)
                            .background(
                                viewModel.isPaused ? Color.green : Color.white.opacity(0.15),
                                in: Circle()
                            )
                            .overlay(
                                Circle()
                                    .stroke(viewModel.isPaused ? Color.green.opacity(0.5) : Color.white.opacity(0.2), lineWidth: 2)
                            )
                    }

                    // Stop — large circle with ring (like Start Trip)
                    Button {
                        Haptics.success()
                        viewModel.toggleRecording()
                    } label: {
                        ZStack {
                            // Outer ring
                            Circle()
                                .stroke(AppTheme.red.opacity(0.4), lineWidth: 3)
                                .frame(width: 82, height: 82)

                            // Inner filled circle
                            Circle()
                                .fill(AppTheme.red)
                                .frame(width: 68, height: 68)

                            // Stop icon
                            Image(systemName: "stop.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }

                    // Spacer to balance pause button
                    Color.clear.frame(width: 48, height: 48)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, safeAreaBottom + 8)
            .frame(maxWidth: .infinity)
            .background(Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.85))
            .background(.ultraThinMaterial)
        }
        .ignoresSafeArea(edges: [.top, .bottom])
    }

    private func statItem(value: String, unit: String?, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            if let unit {
                Text(unit)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var speedColor: Color {
        let s = viewModel.speed
        if s < 40 { return .green }
        if s < 80 { return AppTheme.accent }
        return AppTheme.red
    }

    // MARK: - Back Button (shared between idle and recording)

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

    private func dismissSummary() {
        viewModel.lastCompletedTrip = nil
    }

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
