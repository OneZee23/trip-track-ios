import SwiftUI
import MapKit
import Combine

@MainActor
final class MapViewModel: ObservableObject {
    // MARK: - Map State
    @Published var userTrackingMode: MKUserTrackingMode = .follow
    @Published var isDarkMap: Bool = false

    // MARK: - Recording State
    @Published var isRecording: Bool = false
    @Published var speed: Double = 0        // km/h
    @Published var altitude: Double = 0     // meters
    @Published var distance: Double = 0     // km
    @Published var duration: String = "00:00"
    @Published var gpsAccuracy: Double = 0  // meters
    @Published var trackOverlays: [MKOverlay] = []
    @Published var pendingBadges: [(badge: Badge, count: Int)] = []
    @Published var showBadgeCelebration: Bool = false
    @Published var lastCompletedTrip: Trip?
    @Published var lastCompletionData: TripCompletionData?
    @Published var isPaused: Bool = false
    @Published var discardedJunkTrip: Bool = false

    // MARK: - Camera (idle mode only)
    @Published var zoomDelta: Double = 0
    @Published var currentCameraDistance: Double = 1000

    private static let minCameraDistance: Double = 200
    private static let maxCameraDistance: Double = 15_000_000

    var canZoomIn: Bool { currentCameraDistance > Self.minCameraDistance }
    var canZoomOut: Bool { currentCameraDistance < Self.maxCameraDistance }

    // MARK: - Cached Stats (loaded once, refreshed on stop)
    @Published var cachedTotalKm: Double = 0
    @Published var cachedTripCount: Int = 0

    /// Reads selectedVehicleId from settings entity at recording start
    private var selectedVehicleId: UUID? {
        gamificationManager.fetchSettingsEntity()?.selectedVehicleId
    }

    // MARK: - Dependencies
    var locationManager: LocationManager
    let tripManager: TripManager
    let trackManager = SmoothTrackManager()
    let gamificationManager = GamificationManager()
    let territoryManager = TerritoryManager()
    let roadCollectionManager = RoadCollectionManager()

    private var cancellables = Set<AnyCancellable>()
    private var durationTimer: AnyCancellable?
    private var recordingStartDate: Date?
    private var pausedAccumulated: TimeInterval = 0
    private var pauseStartDate: Date?
    private var sunCheckTimer: AnyCancellable?
    private var speedDecayTimer: AnyCancellable?
    private var lastSpeedUpdate: Date = .distantPast
    private var smoothedSpeed: Double = 0
    private static let speedEMAAlpha: Double = 0.3
    private var mainTrackOverlay: MKPolyline?
    private var headOverlay: GlowingHeadOverlay?
    private var lastOverlayUpdate: Date = .distantPast

    init() {
        let manager = LocationManager()
        self.locationManager = manager
        self.tripManager = TripManager(locationManager: manager)

        setupRecordingBindings()
        setupSunBasedTheme()
        refreshTripStats()

        Task { @MainActor [tripManager, gamificationManager, territoryManager] in
            tripManager.backfillPreviewPolylines()
            tripManager.migrateRegionsIfNeeded()

            let allTrips = tripManager.fetchTrips()
            let settingsEntity = gamificationManager.fetchSettingsEntity()
            gamificationManager.backfillIfNeeded(trips: allTrips, settingsEntity: settingsEntity)

            territoryManager.backfillIfNeeded()
            gamificationManager.backfillBadgesIfNeeded(trips: allTrips)
        }
    }

    // MARK: - Location

    func requestLocationPermission() {
        locationManager.startRealGPS()
    }

    func stopLocationUpdates() {
        locationManager.stopRealGPS()
    }

    // MARK: - Tracking Mode

    func cycleTrackingMode() {
        switch userTrackingMode {
        case .none:
            userTrackingMode = .follow
        case .follow:
            userTrackingMode = .followWithHeading
        case .followWithHeading:
            userTrackingMode = .none
        @unknown default:
            userTrackingMode = .none
        }

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    func zoomIn() {
        zoomDelta = 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func zoomOut() {
        zoomDelta = -1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Recording

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func togglePause() {
        guard isRecording else { return }
        isPaused.toggle()
        tripManager.isPaused = isPaused
        if isPaused {
            pauseStartDate = Date()
            durationTimer?.cancel()
            durationTimer = nil
        } else {
            if let pauseStart = pauseStartDate {
                pausedAccumulated += Date().timeIntervalSince(pauseStart)
                pauseStartDate = nil
            }
            durationTimer = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    self?.updateDuration()
                }
        }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func startRecording() {
        // Reset state
        isPaused = false
        tripManager.isPaused = false
        recordingStartDate = Date()
        pausedAccumulated = 0
        pauseStartDate = nil

        smoothedSpeed = 0

        // Reset track
        trackManager.reset()
        trackManager.startAnimation()
        mainTrackOverlay = nil
        headOverlay = nil
        trackOverlays = []

        // Start trip in CoreData
        tripManager.startTrip(vehicleId: selectedVehicleId)
        isRecording = true

        // Simple follow mode — no zoom management
        userTrackingMode = .follow

        // Duration timer
        durationTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateDuration()
            }

        // Sun-based theme check during recording
        sunCheckTimer = Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let loc = self.locationManager.currentLocation else { return }
                self.updateThemeForSun(coordinate: loc.coordinate)
            }

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func stopRecording() {
        let completedTrip = tripManager.stopTrip()
        trackManager.stopAnimation()
        isRecording = false
        isPaused = false
        tripManager.isPaused = false
        userTrackingMode = .follow
        durationTimer?.cancel()
        durationTimer = nil
        sunCheckTimer?.cancel()
        sunCheckTimer = nil
        speedDecayTimer?.cancel()
        speedDecayTimer = nil
        mainTrackOverlay = nil
        headOverlay = nil
        trackOverlays = []
        speed = 0
        altitude = 0
        distance = 0
        duration = "00:00"

        // Auto-delete junk trips (< 500m AND < 2 min)
        if let trip = completedTrip,
           trip.distance < 500 && trip.duration < 120 {
            tripManager.deleteTrip(id: trip.id)
            discardedJunkTrip = true
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            refreshTripStats()
            return
        }

        // Refresh cached stats after trip ends
        refreshTripStats()

        // Store completed trip for summary screen
        lastCompletedTrip = completedTrip

        // Process gamification — use lightweight fetch (no track points for historical trips).
        // The completedTrip already has track points from the recording session.
        if let trip = completedTrip {
            var allTrips = tripManager.fetchTrips()
            // Replace the lightweight version with the full trip (has track points)
            if let idx = allTrips.firstIndex(where: { $0.id == trip.id }) {
                allTrips[idx] = trip
            }
            let settingsEntity = gamificationManager.fetchSettingsEntity()
            let vehicleEntity = gamificationManager.fetchVehicleEntity(id: trip.vehicleId)

            let completionData = gamificationManager.processCompletedTrip(
                trip: trip,
                allTrips: allTrips,
                settingsEntity: settingsEntity,
                vehicleEntity: vehicleEntity
            )

            // Save earned badge IDs to trip entity
            let earnedIds = completionData.newBadges.map(\.id)
            tripManager.saveBadgesJSON(tripId: trip.id, badgeIds: earnedIds)

            // Process road collection
            var finalData = completionData
            finalData.roadCard = roadCollectionManager.processTrip(trip)
            lastCompletionData = finalData

            // Store badges to show after summary sheet is dismissed
            pendingBadges = completionData.newBadges.map { badge in
                let count = completionData.repeatedBadgeCounts[badge.id] ?? 1
                return (badge: badge, count: count)
            }
        }

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    func refreshTripStats() {
        let stats = tripManager.fetchTripStats()
        cachedTotalKm = stats.totalDistance / 1000.0
        cachedTripCount = stats.count
    }

    private func setupRecordingBindings() {
        // Location updates → speed + track points
        locationManager.$currentLocation
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let self else { return }
                let rawSpeed = max(0, update.speed)
                let speedKmh = rawSpeed < 1.0 ? 0 : rawSpeed * 3.6

                // After a background gap (>3s without updates), reset EMA
                // so speed immediately shows the real value
                let gap = Date().timeIntervalSince(self.lastSpeedUpdate)
                if gap > 3.0 {
                    self.smoothedSpeed = speedKmh
                } else {
                    let alpha = Self.speedEMAAlpha
                    self.smoothedSpeed = alpha * speedKmh + (1 - alpha) * self.smoothedSpeed
                }
                self.speed = self.smoothedSpeed

                self.lastSpeedUpdate = Date()
                self.altitude = update.altitude
                self.gpsAccuracy = update.horizontalAccuracy

                if self.isRecording && !self.isPaused {
                    self.trackManager.addPoint(update.coordinate)
                    self.territoryManager.recordVisit(coordinate: update.coordinate)
                }
            }
            .store(in: &cancellables)

        // Speed decay: if no GPS update for 2s, gradually reduce speed to 0
        speedDecayTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.isRecording, self.speed > 0 else { return }
                let elapsed = Date().timeIntervalSince(self.lastSpeedUpdate)
                if elapsed > 2.0 {
                    // Gradual decay over ~1.5 seconds (3 ticks at 0.5s interval)
                    let decayed = self.speed * 0.4
                    self.speed = decayed < 1 ? 0 : decayed
                    self.smoothedSpeed = self.speed
                }
            }

        // Main track overlay (confirmed points — solid line, throttled to max 2x/sec)
        trackManager.$confirmedPoints
            .receive(on: DispatchQueue.main)
            .sink { [weak self] points in
                guard let self, self.isRecording, points.count >= 2 else { return }
                let now = Date()
                guard now.timeIntervalSince(self.lastOverlayUpdate) >= 0.5 else { return }
                self.lastOverlayUpdate = now
                var coords = points
                self.mainTrackOverlay = MKPolyline(coordinates: &coords, count: coords.count)
                self.updateTrackOverlays()
            }
            .store(in: &cancellables)

        // Head segment overlay (animated, glowing)
        trackManager.$headSegmentPoints
            .receive(on: DispatchQueue.main)
            .sink { [weak self] points in
                guard let self, self.isRecording, points.count >= 2 else { return }
                self.headOverlay = GlowingHeadOverlay(coordinates: points)
                self.updateTrackOverlays()
            }
            .store(in: &cancellables)

        // Trip distance
        tripManager.$activeTrip
            .compactMap { $0?.distanceKm }
            .receive(on: DispatchQueue.main)
            .assign(to: &$distance)
    }

    private func updateTrackOverlays() {
        var overlays: [MKOverlay] = []
        if let main = mainTrackOverlay { overlays.append(main) }
        if let head = headOverlay { overlays.append(head) }
        trackOverlays = overlays
    }

    private func updateDuration() {
        guard isRecording, let start = recordingStartDate else {
            duration = "00:00"
            return
        }
        let totalSeconds = Int(Date().timeIntervalSince(start) - pausedAccumulated)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            duration = String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            duration = String(format: "%02d:%02d", minutes, seconds)
        }
    }

    // MARK: - Sun-Based Theme

    private func setupSunBasedTheme() {
        // Check once when first location arrives
        locationManager.$currentLocation
            .compactMap { $0 }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                self?.updateThemeForSun(coordinate: update.coordinate)
            }
            .store(in: &cancellables)
    }

    private func updateThemeForSun(coordinate: CLLocationCoordinate2D) {
        isDarkMap = SunCalculator.isNight(at: coordinate)
    }

    func checkSunTheme() {
        guard let loc = locationManager.currentLocation else { return }
        updateThemeForSun(coordinate: loc.coordinate)
    }
}
