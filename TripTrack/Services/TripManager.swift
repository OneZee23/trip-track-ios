import Foundation
import CoreData
import Combine
import CoreLocation
import UIKit

final class TripManager: ObservableObject {
    @Published var activeTrip: Trip?
    @Published var isRecording = false

    var isPaused: Bool = false

    /// Kalman filter for GPS smoothing and gap prediction
    let kalmanFilter = KalmanLocationFilter()

    private let repository: TripRepository

    private let locationManager: LocationManager
    private let persistenceController: PersistenceController
    private var cancellables = Set<AnyCancellable>()
    private var activeTripEntity: TripEntity?
    private var lastLocation: CLLocation?
    private var unsavedPointCount = 0
    private var lastSaveTime = Date()
    private let saveBatchSize = 10
    private let saveInterval: TimeInterval = 15

    init(locationManager: LocationManager, persistenceController: PersistenceController = .shared, repository: TripRepository? = nil) {
        self.locationManager = locationManager
        self.persistenceController = persistenceController
        self.repository = repository ?? CoreDataTripRepository(persistenceController: persistenceController)

        locationManager.$currentLocation
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (update: LocationUpdate) in
                self?.handleNewLocation(update.toCLLocation())
            }
            .store(in: &cancellables)

        // Auto-retry geocoding when network comes back
        CacheManager.shared.networkRestored
            .sink { [weak self] in
                self?.retryGeocodingForUntitledTrips()
            }
            .store(in: &cancellables)

        cleanupOrphanedTrips()
    }

    func startTrip(vehicleId: UUID? = nil) {
        let context = persistenceController.container.viewContext
        let entity = TripEntity(context: context)
        entity.id = UUID()
        entity.startDate = Date()
        entity.distance = 0
        entity.maxSpeed = 0
        entity.averageSpeed = 0
        entity.vehicleId = vehicleId
        entity.fuelCurrency = FuelCurrency.current
        entity.lastModifiedAt = Date()
        entity.userId = SettingsManager.shared.localUserId
        persistenceController.save()

        activeTripEntity = entity
        guard let tripId = entity.id, let startDate = entity.startDate else { return }
        activeTrip = Trip(
            id: tripId,
            startDate: startDate
        )
        isRecording = true
        lastLocation = nil
        unsavedPointCount = 0
        lastSaveTime = Date()
        kalmanFilter.reset()
        locationManager.startTracking()
    }

    /// Backdate the active trip's start time (for auto-start recovery)
    func backdateTrip(to date: Date) {
        guard let entity = activeTripEntity else { return }
        entity.startDate = date
        activeTrip = activeTrip.map { trip in
            var updated = trip
            updated.startDate = date
            return updated
        }
        persistenceController.save()
    }

    @discardableResult
    func stopTrip() -> Trip? {
        locationManager.stopTracking()
        isRecording = false

        guard let entity = activeTripEntity else { return nil }
        entity.endDate = Date()
        entity.lastModifiedAt = Date()
        updateEntityStats(entity)
        generatePreviewPolyline(for: entity)
        persistenceController.save()

        let completedTrip = entity.id.flatMap { repository.fetchTripDetail(id: $0) }

        geocodeAndNameTrip(entity: entity)
        deleteDemoTripIfNeeded()

        activeTrip = nil
        activeTripEntity = nil
        lastLocation = nil

        return completedTrip
    }

    func fetchTrips() -> [Trip] {
        repository.fetchAllTrips()
    }

    func fetchTrips(limit: Int, offset: Int) -> [Trip] {
        repository.fetchTrips(limit: limit, offset: offset)
    }

    func fetchTripsModifiedSince(_ date: Date) -> [Trip] {
        repository.fetchTripsModifiedSince(date)
    }

    func fetchTripsWithTrackPoints() -> [Trip] {
        repository.fetchTripsWithTrackPoints()
    }

    func fetchTripCount() -> Int {
        repository.fetchTripCount()
    }

    func fetchLastTripDate() -> Date? {
        repository.fetchLastTripDate()
    }

    func fetchTripStats() -> (count: Int, totalDistance: Double) {
        repository.fetchTripStats()
    }

    func fetchTotalDistance() -> Double {
        repository.fetchTotalDistance()
    }

    func deleteTrip(id: UUID) {
        repository.deleteTrip(id: id)
    }

    func purgeSoftDeletedTrips() {
        repository.purgeSoftDeletedTrips()
    }

    func tripDetail(id: UUID) -> Trip? {
        repository.fetchTripDetail(id: id)
    }

    // MARK: - Orphan Cleanup & Recovery

    /// Max age for a restorable orphan trip (1 hour). Older orphans are closed.
    private static let maxRestorableAge: TimeInterval = 3600

    /// Called on init: finds trips with no endDate (app was killed mid-recording).
    /// Recent orphans (< 1 hour) are restored as active recording.
    /// Old orphans are closed or deleted (junk).
    private func cleanupOrphanedTrips() {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "endDate == nil")

        guard let orphans = try? context.fetch(request), !orphans.isEmpty else { return }

        for entity in orphans {
            let points = (entity.trackPoints?.array as? [TrackPointEntity]) ?? []

            if points.isEmpty {
                context.delete(entity)
                continue
            }

            let lastTimestamp = points.compactMap { $0.timestamp }.max() ?? Date()
            let actualDuration = max(0, entity.startDate.map { lastTimestamp.timeIntervalSince($0) } ?? 0)
            let isJunk = entity.distance < 500 && actualDuration < 120

            if isJunk {
                context.delete(entity)
                continue
            }

            // Recent orphan — restore as active recording
            let age = Date().timeIntervalSince(lastTimestamp)
            if age < Self.maxRestorableAge {
                activeTripEntity = entity
                guard let tripId = entity.id, let startDate = entity.startDate else { continue }
                activeTrip = Trip(
                    id: tripId,
                    startDate: startDate,
                    distance: entity.distance,
                    maxSpeed: entity.maxSpeed,
                    averageSpeed: entity.averageSpeed
                )
                isRecording = true
                lastLocation = nil
                unsavedPointCount = 0
                lastSaveTime = Date()
                kalmanFilter.reset()
                locationManager.startTracking()
            } else {
                entity.endDate = lastTimestamp
            }
        }

        persistenceController.save()
    }

    // MARK: - Private

    private let maxRecordAccuracy: Double = 30.0  // reject points with accuracy > 30m
    private let minRecordDistance: Double = 5.0   // ignore points closer than 5m to last
    private let driftSpeedThreshold: Double = 1.0  // m/s — GPS reports "stationary"
    private let driftCalcSpeedLimit: Double = 5.0  // m/s — but distance says "moving"

    private func handleNewLocation(_ location: CLLocation) {
        guard isRecording, !isPaused, let entity = activeTripEntity else { return }

        // Filter: reject poor accuracy (check raw GPS before Kalman)
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= maxRecordAccuracy else { return }

        // Smooth through Kalman filter
        let filtered = kalmanFilter.processGPSUpdate(location)

        // Filter: minimum distance between stored points (on filtered position)
        if let last = lastLocation {
            let delta = filtered.distance(from: last)
            guard delta >= minRecordDistance else { return }

            // Filter: GPS drift — device reports low speed but calculated distance is high
            let timeDelta = filtered.timestamp.timeIntervalSince(last.timestamp)
            if timeDelta > 0 {
                let calculatedSpeed = delta / timeDelta
                if filtered.speed < driftSpeedThreshold && calculatedSpeed > driftCalcSpeedLimit {
                    return
                }
            }
        }

        let context = persistenceController.container.viewContext
        let point = TrackPointEntity(context: context)
        point.id = UUID()
        point.latitude = filtered.coordinate.latitude
        point.longitude = filtered.coordinate.longitude
        point.altitude = filtered.altitude
        point.speed = max(0, filtered.speed)
        point.course = filtered.course
        point.horizontalAccuracy = filtered.horizontalAccuracy
        point.timestamp = filtered.timestamp
        point.trip = entity

        // Update distance (use filtered position, not raw GPS)
        if let last = lastLocation {
            let delta = filtered.distance(from: last)
            if delta < 1000 { // ignore jumps > 1km
                entity.distance += delta
            }
        }
        lastLocation = filtered

        // Update speeds
        let speed = max(0, filtered.speed)
        if speed > entity.maxSpeed {
            entity.maxSpeed = speed
        }

        // Calculate average speed from distance/time
        if let start = entity.startDate {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > 0 {
                entity.averageSpeed = entity.distance / elapsed
            }
        }

        // Update published trip immediately
        guard let tripId = entity.id, let tripStart = entity.startDate else { return }
        activeTrip = Trip(
            id: tripId,
            startDate: tripStart,
            distance: entity.distance,
            maxSpeed: entity.maxSpeed,
            averageSpeed: entity.averageSpeed,
            trackPoints: [] // don't load all points during tracking
        )

        // Batch saves: persist every N points or every M seconds
        unsavedPointCount += 1
        let timeSinceLastSave = Date().timeIntervalSince(lastSaveTime)
        if unsavedPointCount >= saveBatchSize || timeSinceLastSave >= saveInterval {
            unsavedPointCount = 0
            lastSaveTime = Date()
            persistenceController.saveAsync()
        }
    }

    /// Max single-segment distance considered valid (rejects GPS jumps)
    private let maxSegmentDistance: Double = 1000  // 1km

    private func updateEntityStats(_ entity: TripEntity) {
        guard let points = entity.trackPoints?.array as? [TrackPointEntity],
              points.count > 1 else { return }

        var totalDistance: Double = 0
        var maxSpeed: Double = 0

        for i in 1..<points.count {
            let prev = CLLocation(latitude: points[i-1].latitude, longitude: points[i-1].longitude)
            let curr = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            let segmentDist = curr.distance(from: prev)

            // Skip GPS jumps (same filter as live recording)
            guard segmentDist < maxSegmentDistance else { continue }

            // Skip segments with implausible speed (> 300 km/h ≈ 83 m/s)
            if let prevTS = points[i-1].timestamp, let currTS = points[i].timestamp {
                let dt = currTS.timeIntervalSince(prevTS)
                if dt > 0 && segmentDist / dt > 83.0 { continue }
            }

            totalDistance += segmentDist
            maxSpeed = max(maxSpeed, points[i].speed)
        }

        entity.distance = totalDistance
        entity.maxSpeed = maxSpeed

        if let start = entity.startDate, let end = entity.endDate {
            let elapsed = end.timeIntervalSince(start)
            entity.averageSpeed = elapsed > 0 ? totalDistance / elapsed : 0
        }
    }

    // MARK: - Geocoding (with persistent cache)

    /// TTL for geocoding cache entries (90 days)
    private static let geocodeCacheTTL: TimeInterval = 90 * 24 * 3600

    private func geocodeAndNameTrip(entity: TripEntity) {
        guard let points = entity.trackPoints?.array as? [TrackPointEntity],
              let first = points.first, let last = points.last else { return }

        let startCoord = CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)
        let endCoord = CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)
        let startLoc = CLLocation(latitude: first.latitude, longitude: first.longitude)
        let endLoc = CLLocation(latitude: last.latitude, longitude: last.longitude)

        // Try cache first
        let cachedStart = lookupGeocodeCache(for: startCoord)
        let cachedEnd = lookupGeocodeCache(for: endCoord)

        // If both cached, skip network entirely
        if let cs = cachedStart {
            let isCircular = startLoc.distance(from: endLoc) < 20_000
            if isCircular {
                Task { @MainActor [weak self] in
                    guard !entity.isDeleted else { return }
                    entity.title = cs.locality ?? Self.dateFallbackTitle(for: entity.startDate)
                    entity.region = cs.region
                    entity.lastModifiedAt = Date()
                    self?.persistenceController.save()
                }
                return
            }
            if let ce = cachedEnd {
                let title = Self.buildTitle(start: cs.locality, end: ce.locality, fallbackDate: entity.startDate)
                Task { @MainActor [weak self] in
                    guard !entity.isDeleted else { return }
                    entity.title = title
                    entity.region = cs.region
                    entity.lastModifiedAt = Date()
                    self?.persistenceController.save()
                }
                return
            }
        }

        // Skip network if offline
        if CacheManager.shared.isOffline { return }

        CLGeocoder().reverseGeocodeLocation(startLoc) { [weak self] startPMs, _ in
            let startName = Self.localityName(from: startPMs?.first)
            let startRegion = Self.regionName(from: startPMs?.first)

            Task { @MainActor [weak self] in
                self?.saveGeocodeCache(for: startCoord, locality: startName, region: startRegion)

                // Circular route (< 20 km between start and finish)
                if startLoc.distance(from: endLoc) < 20_000 {
                    guard !entity.isDeleted else { return }
                    entity.title = startName ?? Self.dateFallbackTitle(for: entity.startDate)
                    entity.region = startRegion
                    entity.lastModifiedAt = Date()
                    self?.persistenceController.save()
                    return
                }

                // Check end cache before making second network call
                if let ce = cachedEnd {
                    guard !entity.isDeleted else { return }
                    entity.title = Self.buildTitle(start: startName, end: ce.locality, fallbackDate: entity.startDate)
                    entity.region = startRegion
                    entity.lastModifiedAt = Date()
                    self?.persistenceController.save()
                    return
                }

                // A → B route — geocode end point
                CLGeocoder().reverseGeocodeLocation(endLoc) { [weak self] endPMs, _ in
                    let endName = Self.localityName(from: endPMs?.first)

                    Task { @MainActor [weak self] in
                        self?.saveGeocodeCache(for: endCoord, locality: endName, region: Self.regionName(from: endPMs?.first))

                        guard !entity.isDeleted else { return }
                        entity.title = Self.buildTitle(start: startName, end: endName, fallbackDate: entity.startDate)
                        entity.region = startRegion
                        entity.lastModifiedAt = Date()
                        self?.persistenceController.save()
                    }
                }
            }
        }
    }

    private static func localityName(from placemark: CLPlacemark?) -> String? {
        placemark?.locality ?? placemark?.subAdministrativeArea ?? placemark?.administrativeArea
    }

    private static func regionName(from placemark: CLPlacemark?) -> String? {
        placemark?.administrativeArea
    }

    private static func buildTitle(start: String?, end: String?, fallbackDate: Date?) -> String {
        switch (start, end) {
        case let (s?, e?): "\(s) → \(e)"
        case let (s?, nil): s
        case let (nil, e?): e
        case (nil, nil): dateFallbackTitle(for: fallbackDate)
        }
    }

    /// Reverse-geocode only the region for an entity's first track point.
    private func geocodeRegion(for entity: TripEntity, completion: @escaping () -> Void) {
        guard !entity.isDeleted,
              let points = entity.trackPoints?.array as? [TrackPointEntity],
              let first = points.first else {
            completion()
            return
        }

        let coord = CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)

        // Check cache first
        if let cached = lookupGeocodeCache(for: coord), cached.region != nil {
            Task { @MainActor [weak self] in
                guard !entity.isDeleted else { return }
                entity.region = cached.region
                entity.lastModifiedAt = Date()
                self?.persistenceController.save()
            }
            completion()
            return
        }

        // Skip network if offline
        guard !CacheManager.shared.isOffline else {
            completion()
            return
        }

        let location = CLLocation(latitude: first.latitude, longitude: first.longitude)
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            let adminArea = placemarks?.first?.administrativeArea
            let locality = Self.localityName(from: placemarks?.first)

            Task { @MainActor [weak self] in
                self?.saveGeocodeCache(for: coord, locality: locality, region: adminArea)

                if let adminArea {
                    guard !entity.isDeleted else { return }
                    entity.region = adminArea
                    entity.lastModifiedAt = Date()
                    self?.persistenceController.save()
                }
                completion()
            }
        }
    }

    // MARK: - Geocode Cache (CoreData)

    private struct GeocodeCacheResult {
        let locality: String?
        let region: String?
    }

    private func lookupGeocodeCache(for coord: CLLocationCoordinate2D) -> GeocodeCacheResult? {
        let geohash = GeohashEncoder.encode(latitude: coord.latitude, longitude: coord.longitude, precision: 5)
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<GeocodeCacheEntity> = GeocodeCacheEntity.fetchRequest()
        request.predicate = NSPredicate(format: "geohash5 == %@", geohash)
        request.fetchLimit = 1

        guard let entity = try? context.fetch(request).first else { return nil }

        // Check TTL — defer delete to avoid synchronous save during lookup
        if let cachedAt = entity.cachedAt,
           Date().timeIntervalSince(cachedAt) > Self.geocodeCacheTTL {
            context.delete(entity)
            persistenceController.saveAsync()
            return nil
        }

        return GeocodeCacheResult(locality: entity.locality, region: entity.region)
    }

    private func saveGeocodeCache(for coord: CLLocationCoordinate2D, locality: String?, region: String?) {
        let geohash = GeohashEncoder.encode(latitude: coord.latitude, longitude: coord.longitude, precision: 5)
        let context = persistenceController.container.viewContext

        // Upsert: check if entry already exists
        let request: NSFetchRequest<GeocodeCacheEntity> = GeocodeCacheEntity.fetchRequest()
        request.predicate = NSPredicate(format: "geohash5 == %@", geohash)
        request.fetchLimit = 1

        let entity: GeocodeCacheEntity
        if let existing = try? context.fetch(request).first {
            entity = existing
        } else {
            entity = GeocodeCacheEntity(context: context)
            entity.geohash5 = geohash
        }

        entity.locality = locality
        entity.region = region
        entity.cachedAt = Date()
        persistenceController.save()
    }

    // MARK: - Track Processing Migration

    /// Mark all existing trips as track-processed (one-time migration).
    /// Without this, the new isTrackProcessed field defaults to false,
    /// causing PostTripTrackProcessor to incorrectly process all old trips.
    func migrateMarkExistingTripsProcessed() {
        let key = "didMigrateTrackProcessed"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let context = persistenceController.container.viewContext

        // 1. Remove any incorrectly added interpolated points from all trips
        let pointRequest: NSFetchRequest<TrackPointEntity> = TrackPointEntity.fetchRequest()
        pointRequest.predicate = NSPredicate(format: "isInterpolated == YES")
        if let interpolatedPoints = try? context.fetch(pointRequest), !interpolatedPoints.isEmpty {
            for point in interpolatedPoints {
                context.delete(point)
            }
        }

        // 2. Mark all existing completed trips as processed
        let tripRequest: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        tripRequest.predicate = NSPredicate(format: "endDate != nil AND isTrackProcessed == NO")
        if let entities = try? context.fetch(tripRequest), !entities.isEmpty {
            for entity in entities {
                entity.isTrackProcessed = true
            }
        }

        persistenceController.save()

        // 3. Regenerate preview polylines (in case some were corrupted by interpolated points)
        backfillPreviewPolylines()

        UserDefaults.standard.set(true, forKey: key)
    }

    /// Re-process all trips with spike removal (one-time, v2 of track processing).
    func migrateReprocessTripsWithSpikeRemoval() {
        let key = "didMigrateTrackSpikeRemovalV2"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let context = persistenceController.container.viewContext

        // 1. Remove old interpolated points
        let pointRequest: NSFetchRequest<TrackPointEntity> = TrackPointEntity.fetchRequest()
        pointRequest.predicate = NSPredicate(format: "isInterpolated == YES")
        if let interpolatedPoints = try? context.fetch(pointRequest), !interpolatedPoints.isEmpty {
            for point in interpolatedPoints {
                context.delete(point)
            }
        }

        // 2. Reset isTrackProcessed on all trips so PostTripTrackProcessor reprocesses them
        let tripRequest: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        tripRequest.predicate = NSPredicate(format: "endDate != nil AND isTrackProcessed == YES")
        if let entities = try? context.fetch(tripRequest), !entities.isEmpty {
            for entity in entities {
                entity.isTrackProcessed = false
            }
        }

        persistenceController.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    // MARK: - Region Migration

    /// Re-geocode region field for trips missing region data
    func migrateRegionsIfNeeded() {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "endDate != nil AND region == nil AND syncStatus != %d", SyncStatus.pendingDelete.rawValue)

        guard let entities = try? context.fetch(request), !entities.isEmpty else { return }

        migrateRegionSequentially(entities: entities, index: 0)
    }

    private func migrateRegionSequentially(entities: [TripEntity], index: Int) {
        guard index < entities.count else { return }

        geocodeRegion(for: entities[index]) { [weak self] in
            // CLGeocoder recommends max 1 request per second
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                self?.migrateRegionSequentially(entities: entities, index: index + 1)
            }
        }
    }

    private static let dateFallbackFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM, HH:mm"
        return f
    }()

    private static func dateFallbackTitle(for date: Date?) -> String {
        guard let date else { return "Trip" }
        return dateFallbackFormatter.string(from: date)
    }

    // MARK: - Demo Trip

    private static let demoTripIdKey = "demoTripId"

    // MARK: - Demo Trip (debug only, not used in production since 0.1.1)

    func createDemoTrip() {
        let context = persistenceController.container.viewContext
        let entity = TripEntity(context: context)
        let tripId = UUID()
        entity.id = tripId
        entity.startDate = Calendar.current.date(byAdding: .hour, value: -2, to: Date())
        entity.endDate = Calendar.current.date(byAdding: .hour, value: -1, to: Date())
        entity.title = "Demo trip"
        entity.region = "Demo"
        entity.distance = 42_500
        entity.maxSpeed = 28.0
        entity.averageSpeed = 12.0

        // ~20 points along a scenic route
        let demoCoords: [(Double, Double)] = [
            (55.7558, 37.6173), (55.7600, 37.6250), (55.7650, 37.6350),
            (55.7700, 37.6450), (55.7750, 37.6550), (55.7800, 37.6650),
            (55.7850, 37.6750), (55.7900, 37.6850), (55.7950, 37.6950),
            (55.8000, 37.7050), (55.8050, 37.7150), (55.8100, 37.7250),
            (55.8150, 37.7350), (55.8200, 37.7450), (55.8250, 37.7550),
            (55.8300, 37.7650), (55.8350, 37.7750), (55.8400, 37.7850),
            (55.8450, 37.7950), (55.8500, 37.8050),
        ]

        guard let startTime = entity.startDate else { return }
        for (i, coord) in demoCoords.enumerated() {
            let point = TrackPointEntity(context: context)
            point.id = UUID()
            point.latitude = coord.0
            point.longitude = coord.1
            point.altitude = 150.0 + Double(i) * 2
            point.speed = Double.random(in: 8...28)
            point.course = 45.0
            point.horizontalAccuracy = 5.0
            point.timestamp = startTime.addingTimeInterval(Double(i) * 180)
            point.trip = entity
        }

        persistenceController.save()
        UserDefaults.standard.set(tripId.uuidString, forKey: Self.demoTripIdKey)
    }

    func deleteDemoTripIfNeeded() {
        guard let demoIdString = UserDefaults.standard.string(forKey: Self.demoTripIdKey),
              let demoId = UUID(uuidString: demoIdString) else { return }

        deleteTrip(id: demoId)
        UserDefaults.standard.removeObject(forKey: Self.demoTripIdKey)
    }

    // MARK: - Per-Trip Badges

    func saveBadgesJSON(tripId: UUID, badgeIds: [String]) {
        repository.saveBadgesJSON(tripId: tripId, badgeIds: badgeIds)
    }

    // MARK: - Preview Polyline

    /// Generate a simplified polyline (~20 points) for feed card previews.
    private func generatePreviewPolyline(for entity: TripEntity) {
        guard let points = entity.trackPoints?.array as? [TrackPointEntity],
              points.count >= 2 else { return }

        let sorted = points.sorted {
            ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast)
        }
        let coords = sorted.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        let simplified = GeometryUtils.simplifyRDP(coords, epsilon: 0.00003)
        entity.previewPolyline = Trip.encodePolyline(simplified)
    }

    /// Backfill preview polylines for existing trips that don't have one.
    func backfillPreviewPolylines() {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "endDate != nil AND previewPolyline == nil")

        guard let entities = try? context.fetch(request), !entities.isEmpty else { return }

        for entity in entities {
            generatePreviewPolyline(for: entity)
        }
        persistenceController.save()
    }

    /// One-time migration: regenerate all preview polylines with correct timestamp sorting.
    func migrateRegeneratePreviewPolylines() {
        let key = "didMigratePreviewPolylinesSorted"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "endDate != nil AND previewPolyline != nil")

        guard let entities = try? context.fetch(request), !entities.isEmpty else {
            UserDefaults.standard.set(true, forKey: key)
            return
        }

        for entity in entities {
            generatePreviewPolyline(for: entity)
        }
        persistenceController.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    // MARK: - Photos

    func addPhoto(to tripId: UUID, image: UIImage, caption: String? = nil) -> TripPhoto? {
        repository.addPhoto(to: tripId, image: image, caption: caption)
    }

    func deletePhoto(id: UUID, from tripId: UUID) {
        repository.deletePhoto(id: id, from: tripId)
    }

    func updateNotes(for tripId: UUID, notes: String) {
        repository.updateNotes(for: tripId, notes: notes)
    }

    func updateTitle(for tripId: UUID, title: String) {
        repository.updateTitle(for: tripId, title: title)
    }

    // MARK: - Geocoding Retry

    private var lastGeocodingRetry: Date = .distantPast

    func retryGeocodingForUntitledTrips() {
        // Don't attempt if offline — will be retried automatically on network restore
        guard !CacheManager.shared.isOffline else { return }
        // Throttle: skip if retried less than 60s ago
        guard Date().timeIntervalSince(lastGeocodingRetry) > 60 else { return }
        lastGeocodingRetry = Date()

        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "title == nil AND trackPoints.@count > 0")

        guard let entities = try? context.fetch(request), !entities.isEmpty else { return }
        // Serialize geocoding to avoid CLGeocoder rate limiting
        geocodeSequentially(entities: entities, index: 0)
    }

    private func geocodeSequentially(entities: [TripEntity], index: Int) {
        guard index < entities.count else { return }
        geocodeAndNameTrip(entity: entities[index])
        // CLGeocoder recommends max 1 request per second
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.geocodeSequentially(entities: entities, index: index + 1)
        }
    }
}
