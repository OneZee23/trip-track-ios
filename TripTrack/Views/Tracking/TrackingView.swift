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
                    bottomInset: viewModel.isRecording ? (tabBarHeight + 120) : idleHUDInset,
                    zoomDelta: $viewModel.zoomDelta,
                    targetCameraDistance: viewModel.targetCameraDistance,
                    onCameraDistanceChanged: { viewModel.currentCameraDistance = $0 }
                )
                .ignoresSafeArea()
            }

            // Loading overlay while map initializes
            if !isMapReady {
                CarLoadingView()
            }

            if viewModel.isRecording {
                recordingOverlay
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                        removal: .opacity
                    ))
            } else {
                idleOverlay
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: viewModel.isRecording)
        .onAppear {
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
                onAddPhoto: { dismissSummary() },
                onAddNotes: { dismissSummary() },
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
            // Top bar: back (left), GPS (right) — flush to safe area top
            HStack {
                backButton
                Spacer()
                GPSIndicatorView(accuracy: viewModel.gpsAccuracy)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            // Map controls — right side
            HStack {
                Spacer()
                mapControls
                    .padding(.trailing, 16)
                    .padding(.bottom, 12)
            }

            // HUD + Stop — flush to bottom edge
            CompactTrackingHUD(
                speed: viewModel.speed,
                altitude: viewModel.altitude,
                distance: viewModel.distance,
                duration: viewModel.duration,
                isPaused: viewModel.isPaused,
                onPause: { viewModel.togglePause() }
            )

            Button {
                Haptics.success()
                viewModel.toggleRecording()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16))
                    Text(lang.language == .ru ? "Завершить" : "Stop trip")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(AppTheme.red, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .ignoresSafeArea(edges: .bottom)
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
            // Top bar: back (left), GPS (center) — flush to safe area top
            HStack {
                backButton
                Spacer()
                GPSIndicatorView(accuracy: viewModel.gpsAccuracy)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

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
        if !viewModel.pendingBadges.isEmpty {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                viewModel.showBadgeCelebration = true
            }
        }
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

#Preview {
    TrackingView()
        .environmentObject(MapViewModel())
        .preferredColorScheme(.dark)
}
