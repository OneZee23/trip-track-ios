import Foundation
import CoreData
import Combine
import CoreLocation
import UIKit
import OSLog

/// Shares the `gps` category so recording-progress lines (points + km) sit next
/// to raw-fix diagnostics and watchdog restarts in the exported log.
private let gpsLog = Logger(subsystem: "com.triptrack", category: "gps")

final class TripManager: ObservableObject {
    @Published var activeTrip: Trip?
    @Published var isRecording = false {
        didSet {
            // Mirror to a static flag so non-instance-holding services
            // (SyncCoordinator, push handlers) can short-circuit without
            // pulling a TripManager reference through their hierarchy.
            Self.isAnyRecording = isRecording
        }
    }

    /// Process-wide "is any TripManager currently recording" flag. Read by
    /// SyncCoordinator to skip pulls that would clobber live state.
    static private(set) var isAnyRecording = false

    var isPaused: Bool = false {
        didSet {
            // Drop the pre-pause fix so the first point after resume doesn't add a
            // cross-pause jump to the distance (a settling/drift fix while parked
            // could otherwise be measured from the spot where pause began).
            if isPaused { lastLocation = nil }
        }
    }

    /// Kalman filter for GPS smoothing and gap prediction
    let kalmanFilter = KalmanLocationFilter()

    let repository: TripRepository

    private let locationManager: LocationManager
    private let persistenceController: PersistenceController
    private var cancellables = Set<AnyCancellable>()
    private var activeTripEntity: TripEntity?

    /// A force-quit recording found at launch (6.1.0 recovery prompt).
    /// Stashed by `cleanupOrphanedTrips`; consumed by `adoptRecoverableOrphan`
    /// when the user picks Continue or Finish&Save in the prompt.
    private(set) var recoverableOrphan: Trip?
    private(set) var recoverableOrphanDuration: TimeInterval = 0
    /// True when the recording stopped only moments ago — the app died while
    /// the person was still driving. See `silentResumeWindow`.
    private(set) var recoverableOrphanIsFresh = false

    /// How stale a recording has to be before we ask about it at all.
    ///
    /// The canon calls this a hybrid, and both extremes are wrong. Always
    /// resuming silently (pre-6.1.0) meant a trip you abandoned three hours
    /// ago quietly kept recording. Always asking (6.1.0 as shipped) meant a
    /// crash at a traffic light put a modal in front of a person who is still
    /// driving — the worst possible moment for a decision. Under fifteen
    /// minutes the answer is obvious enough to not ask for it.
    static let silentResumeWindow: TimeInterval = 15 * 60
    private var recoverableOrphanEntity: TripEntity?

    /// Adopts the stashed orphan as the ACTIVE recording (shared by both
    /// prompt actions — Finish&Save immediately runs the stop pipeline on
    /// top). Returns nil when there is nothing to recover, or when another
    /// recording already started meanwhile (adopting would overwrite the
    /// live activeTripEntity; the orphan stays stashed for the next launch).
    func adoptRecoverableOrphan() -> Trip? {
        guard !isRecording else { return nil }
        guard let entity = recoverableOrphanEntity, let trip = recoverableOrphan else { return nil }
        activeTripEntity = entity
        activeTrip = trip
        isRecording = true
        lastLocation = nil
        unsavedPointCount = 0
        lastSaveTime = Date()
        kalmanFilter.reset()
        locationManager.startTracking()
        recoverableOrphan = nil
        recoverableOrphanEntity = nil
        return trip
    }
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
        // New trips are private by default; owner can toggle visibility from the trip detail.
        entity.isPrivate = true
        persistenceController.save()

        activeTripEntity = entity
        guard let tripId = entity.id, let startDate = entity.startDate else { return }
        // Carry the vehicle into the in-memory Trip too — it's already stamped
        // on the entity above, but consumers reading activeTrip.vehicleId (e.g.
        // the recording UI) would otherwise see nil.
        activeTrip = Trip(
            id: tripId,
            startDate: startDate,
            vehicleId: vehicleId
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
        // Notify the live UI (MapViewModel) so its `recordingStartDate`
        // and the duration timer match the entity's new wall-clock start.
        // Without this, the on-screen timer reads ~0:00 for an auto-trip
        // that actually began 5–10 minutes ago.
        NotificationCenter.default.post(
            name: .tripStartDateBackdated,
            object: date,
        )
    }

    @discardableResult
    func stopTrip(suggestedEndDate: Date? = nil) -> Trip? {
        locationManager.stopTracking()
        isRecording = false

        guard let entity = activeTripEntity else { return nil }
        // Priority: trimmed tail (most precise — uses actual track point
        // timestamps) → caller-supplied hint (e.g. AutoTripService passes the
        // last distance-change time when auto-stopping after stale window) →
        // now. The hint matters when the trip stopped moving but no
        // stationary track points were recorded — `TripManager.handleNewLocation`
        // filters out drift / sub-5m points so a parked-and-quiet tail can
        // contain zero new points, leaving `trimmedEndDate` unable to detect
        // it. Without the hint, an auto-stop fired 15 min after the user
        // really parked would record a 65-min trip for a 50-min drive.
        // Clamped to the start: `suggestedEndDate` comes from the auto-stop's
        // last-movement timestamp, and a stale tracker could hand back a moment
        // from BEFORE this trip began — which persisted a negative duration and
        // a negative average speed, and drew a trip that ended before it
        // started everywhere those two numbers are shown.
        let proposedEnd = trimmedEndDate(for: entity) ?? suggestedEndDate ?? Date()
        entity.endDate = max(proposedEnd, entity.startDate ?? proposedEnd)
        entity.lastModifiedAt = Date()
        updateEntityStats(entity)
        generatePreviewPolyline(for: entity)
        persistenceController.save()

        let completedTrip = entity.id.flatMap { repository.fetchTripDetail(id: $0) }

        geocodeAndNameTrip(entity: entity)
        deleteDemoTripIfNeeded()

        if let tripId = completedTrip?.id {
            Task { @MainActor in
                SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: tripId, action: .upload))
            }
        }

        activeTrip = nil
        activeTripEntity = nil
        lastLocation = nil

        return completedTrip
    }

    /// Returns a trimmed endDate if the trip ends with a stationary tail.
    /// Walks the track points backwards and returns the timestamp of the last
    /// meaningful movement (≥7 km/h, confirmed by an adjacent point also moving).
    /// Only trims when the stationary tail exceeds 60 seconds — short stops at
    /// lights/parking are preserved.
    private func trimmedEndDate(for entity: TripEntity) -> Date? {
        guard let points = (entity.trackPoints?.array as? [TrackPointEntity]),
              points.count > 2 else { return nil }

        let movingThresholdMs: Double = 2.0 // ~7.2 km/h — clearly driving, not parking
        let minTailToTrim: TimeInterval = 60

        // Find the last index where the point AND its predecessor are both moving.
        var lastMovingIdx: Int?
        for i in stride(from: points.count - 1, through: 1, by: -1) {
            if points[i].speed > movingThresholdMs && points[i - 1].speed > movingThresholdMs {
                lastMovingIdx = i
                break
            }
        }

        guard let idx = lastMovingIdx,
              let lastMovingTs = points[idx].timestamp,
              let tailTs = points.last?.timestamp else { return nil }

        let tailDuration = tailTs.timeIntervalSince(lastMovingTs)
        return tailDuration >= minTailToTrim ? lastMovingTs : nil
    }

    func fetchTrips() -> [Trip] {
        repository.fetchAllTrips()
    }

    /// Async variant of `fetchTrips()` for callers that can wait — like the
    /// Feed view's pull-to-refresh handler. Off-loads the CoreData read from
    /// the main thread so the refresh spinner doesn't freeze on iPhone 12+
    /// with sizable trip libraries. Falls back to the sync path for mocked
    /// `TripRepository` implementations in tests.
    func fetchTripsAsync() async -> [Trip] {
        if let coreRepo = repository as? CoreDataTripRepository {
            return await coreRepo.fetchAllTripsAsync()
        }
        return repository.fetchAllTrips()
    }

    func hasAnyPrivateTrip() -> Bool {
        repository.hasAnyPrivateTrip()
    }

    func fetchTrips(limit: Int, offset: Int) -> [Trip] {
        repository.fetchTrips(limit: limit, offset: offset)
    }

    func fetchTripsModifiedSince(_ date: Date) -> [Trip] {
        repository.fetchTripsModifiedSince(date)
    }

    func fetchTripsForMap() -> [Trip] {
        repository.fetchTripsForMap()
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
        // Snapshot photo IDs BEFORE the soft-delete so we can cancel any
        // queued uploads for them. Without this, a `.photo .upload` could
        // run AFTER the trip was deleted client-side, landing a permanent
        // orphan blob in R2 (server cascade only deletes the photo *row*,
        // not the R2 object since the upload pre-creates that key).
        let photoIds = repository.fetchTripDetail(id: id)?.photos.map(\.id) ?? []
        Task { @MainActor in
            SyncQueue.shared.cancelOperations(for: id, entityType: .trip)
            for pid in photoIds {
                SyncQueue.shared.cancelOperations(for: pid, entityType: .photo)
            }
        }
        repository.deleteTrip(id: id)
    }

    func purgeSoftDeletedTrips() {
        repository.purgeSoftDeletedTrips()
    }

    func tripDetail(id: UUID) -> Trip? {
        repository.fetchTripDetail(id: id)
    }

    // MARK: - Orphan Cleanup & Recovery

    /// Max age for a restorable orphan trip. Raised 1h→6h so a long road trip
    /// whose app was killed mid-drive (memory pressure / reboot) still resumes as
    /// ONE track when reopened later the same day, instead of silently splitting.
    /// During a manual pause, location stays active and keeps the app alive, so an
    /// overnight pause survives without needing recovery at all. 6h bounds the
    /// "forgot to stop" case (a far-older orphan is treated as genuinely abandoned).
    private static let maxRestorableAge: TimeInterval = 6 * 3600

    /// Called on init: finds trips with no endDate (app was killed mid-recording).
    /// Recent orphans (< maxRestorableAge) are restored as active recording.
    /// Old orphans are closed or deleted (junk).
    private func cleanupOrphanedTrips() {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "endDate == nil")

        // NOTE: orphan absence must NOT short-circuit the Live Activity sweep
        // below — a trip stopped cleanly (endDate set) leaves zero orphans yet a
        // lingering Lock-Screen card can still outlive the process. So we fetch
        // (possibly empty) and only gate the orphan PROCESSING on non-empty.
        let orphans = (try? context.fetch(request)) ?? []

        if !orphans.isEmpty {
            // First pass: drop empty/junk orphans, collect the rest with their last point time.
            var candidates: [(entity: TripEntity, lastTimestamp: Date)] = []
            for entity in orphans {
                let points = (entity.trackPoints?.array as? [TrackPointEntity]) ?? []

                if points.isEmpty {
                    context.delete(entity)
                    continue
                }

                let lastTimestamp = points.compactMap { $0.timestamp }.max() ?? Date()
                let actualDuration = max(0, entity.startDate.map { lastTimestamp.timeIntervalSince($0) } ?? 0)
                // entity.maxSpeed is m/s — convert to km/h for the shared classifier.
                let maxSpeedKmh = entity.maxSpeed * 3.6
                let isJunk = TripJunkClassifier.isJunk(
                    distanceMeters: entity.distance,
                    durationSeconds: actualDuration,
                    maxSpeedKmh: maxSpeedKmh
                )

                if isJunk {
                    context.delete(entity)
                    continue
                }
                candidates.append((entity, lastTimestamp))
            }

            // Stash at most ONE orphan — the most recent — as RECOVERABLE.
            // 6.1.0 (Figma 505:119): the app no longer silently resumes the
            // recording; a launch-time prompt offers «Продолжить запись» /
            // «Завершить и сохранить» (never discard — non-junk orphans are
            // always preserved). Every OTHER orphan is closed (endDate set)
            // so it can never linger as a zombie that re-triggers recovery.
            let mostRecent = candidates.max { $0.lastTimestamp < $1.lastTimestamp }
            for (entity, lastTimestamp) in candidates {
                let isTheOne = entity === mostRecent?.entity
                let age = Date().timeIntervalSince(lastTimestamp)
                guard isTheOne, age < Self.maxRestorableAge, let tripId = entity.id, let startDate = entity.startDate else {
                    entity.endDate = lastTimestamp // older / too-old / malformed → close it
                    continue
                }
                recoverableOrphanEntity = entity
                recoverableOrphan = Trip(
                    id: tripId,
                    startDate: startDate,
                    distance: entity.distance,
                    maxSpeed: entity.maxSpeed,
                    averageSpeed: entity.averageSpeed,
                    vehicleId: entity.vehicleId
                )
                recoverableOrphanDuration = lastTimestamp.timeIntervalSince(startDate)
                recoverableOrphanIsFresh = age < Self.silentResumeWindow
            }

            persistenceController.save()
        }

        // Sweep ANY lingering Live Activities on launch when we're not
        // actively recording — without this a force-quit leaves the prior
        // banner on Lock Screen / Dynamic Island until iOS times it out (~8h).
        // Runs even with zero orphans (the clean-stop case), which the old
        // early-return skipped. When we DID restore a recording above,
        // isRecording is true, so the live card is correctly left intact.
        // `endActivity()` walks `Activity<TripActivityAttributes>.activities`.
        if !isRecording {
            Task { @MainActor in
                LiveActivityManager.shared.endActivity()
            }
        }
    }

    // MARK: - Private

    // Raised 30→65m so heavy-canopy / remote (taiga) fixes still record instead of
    // every point being dropped (the "0 km after 8h" bug). Jitter from low-accuracy
    // fixes is contained by the accuracy-scaled minimum distance in handleNewLocation.
    private let maxRecordAccuracy: Double = 65.0  // reject points with accuracy > 65m
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

        // Filter: minimum distance between stored points (on filtered position).
        if let last = lastLocation {
            let delta = filtered.distance(from: last)
            // Flat 5m floor. We deliberately do NOT scale this by accuracy: a higher
            // floor on poor (taiga) fixes silently DROPS real slow-movement segments
            // AND their incremental distance, under-counting the odometer exactly
            // where this release is trying to capture more. Jitter is rejected by the
            // drift filter below, not by inflating the distance floor.
            guard delta >= minRecordDistance else { return }

            // Filter: GPS drift — the Kalman velocity says near-stationary but the
            // point-to-point calculated speed is high (parked-but-jittering). Applied
            // UNCONDITIONALLY: `filtered.speed` is the Kalman velocity estimate derived
            // from position (raw GPS speed only refines it when known), so this keeps
            // genuine movement and drops stationary jitter at any accuracy — including
            // 35–65m taiga fixes, where leaving it off would let jitter inflate distance.
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

        // Update distance (use filtered position, not raw GPS). Accept the segment
        // when the IMPLIED speed is plausible — a sparse-GPS / dead-zone bridge
        // (minutes apart in the taiga) can exceed 1km yet be real. A genuine GPS
        // teleport has a tiny dt → impossible implied speed → rejected. Only fall
        // back to the absolute cap when there's no usable time delta.
        if let last = lastLocation {
            let delta = filtered.distance(from: last)
            let dt = filtered.timestamp.timeIntervalSince(last.timestamp)
            if TripDistanceGate.isPlausibleSegment(meters: delta, dt: dt) {
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
            trackPoints: [], // don't load all points during tracking
            vehicleId: entity.vehicleId // keep the car; rebuild would otherwise nil it every fix
        )

        // Batch saves: persist every N points or every M seconds
        unsavedPointCount += 1
        let timeSinceLastSave = Date().timeIntervalSince(lastSaveTime)
        if unsavedPointCount >= saveBatchSize || timeSinceLastSave >= saveInterval {
            unsavedPointCount = 0
            lastSaveTime = Date()
            persistenceController.saveAsync()
            // Recording progress (throttled to the batch cadence): ties accepted
            // fixes to actually-recorded output, so a "GPS dropped" export shows
            // whether distance kept growing or flatlined.
            gpsLog.notice("recording: dist=\(String(format: "%.2f", entity.distance / 1000))km maxSpeed=\(String(format: "%.0f", entity.maxSpeed * 3.6))km/h")
        }
    }

    private func updateEntityStats(_ entity: TripEntity) {
        guard let points = entity.trackPoints?.array as? [TrackPointEntity],
              points.count > 1 else { return }

        var totalDistance: Double = 0
        var maxSpeed: Double = 0

        for i in 1..<points.count {
            let prev = CLLocation(latitude: points[i-1].latitude, longitude: points[i-1].longitude)
            let curr = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            let segmentDist = curr.distance(from: prev)

            // Reject only IMPOSSIBLE-speed segments (real GPS teleport jumps), not
            // long-but-plausible sparse-GPS bridges. Shared gate (TripDistanceGate):
            // implied-speed when we have a usable dt, absolute-cap fallback otherwise.
            var dt: TimeInterval = 0
            if let prevTS = points[i-1].timestamp, let currTS = points[i].timestamp {
                dt = currTS.timeIntervalSince(prevTS)
            }
            if !TripDistanceGate.isPlausibleSegment(meters: segmentDist, dt: dt) { continue }

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
                    if let id = entity.id {
                        SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: id, action: .update))
                    }
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
                    if let id = entity.id {
                        SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: id, action: .update))
                    }
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
                    if let id = entity.id {
                        SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: id, action: .update))
                    }
                    return
                }

                // Check end cache before making second network call
                if let ce = cachedEnd {
                    guard !entity.isDeleted else { return }
                    entity.title = Self.buildTitle(start: startName, end: ce.locality, fallbackDate: entity.startDate)
                    entity.region = startRegion
                    entity.lastModifiedAt = Date()
                    self?.persistenceController.save()
                    if let id = entity.id {
                        SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: id, action: .update))
                    }
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
                        if let id = entity.id {
                            SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: id, action: .update))
                        }
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

    /// APP-language auto-title («5 авг, 17:41» in RU) — the old formatter
    /// followed the SYSTEM locale, so an EN-system device stamped English
    /// titles into a Russian app (and they synced up verbatim).
    private static func dateFallbackTitle(for date: Date?) -> String {
        TripAutoTitle.generate(for: date, language: LanguageManager.currentLanguage)
    }

    // MARK: - Demo Trip

    private static let demoTripIdKey = "demoTripId"
    // Shared by createDemoTrip and the one-shot content sweep so the signature
    // they match on can't drift apart.
    private static let demoTripTitle = "Demo trip"
    private static let demoTripRegion = "Demo"

    // MARK: - Demo Trip (debug only, not used in production since 0.1.1)

    func createDemoTrip() {
        let context = persistenceController.container.viewContext
        let entity = TripEntity(context: context)
        let tripId = UUID()
        entity.id = tripId
        entity.startDate = Calendar.current.date(byAdding: .hour, value: -2, to: Date())
        entity.endDate = Calendar.current.date(byAdding: .hour, value: -1, to: Date())
        entity.title = Self.demoTripTitle
        entity.region = Self.demoTripRegion
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
        // Primary: delete by the stored id (set by createDemoTrip in legacy builds).
        if let demoIdString = UserDefaults.standard.string(forKey: Self.demoTripIdKey),
           let demoId = UUID(uuidString: demoIdString) {
            deleteTrip(id: demoId)
            UserDefaults.standard.removeObject(forKey: Self.demoTripIdKey)
        }

        // Fallback (one-shot): some older installs lost the `demoTripId` key while
        // the seeded "Demo trip" row survived and polluted stats (a tester hit this).
        // Sweep any trip matching the exact createDemoTrip signature — region "Demo"
        // is never produced by real geocoding, so this can't touch a genuine trip.
        let sweepKey = "demoTripContentSweepV057Done"
        guard !UserDefaults.standard.bool(forKey: sweepKey) else { return }
        UserDefaults.standard.set(true, forKey: sweepKey)

        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "title == %@ AND region == %@", Self.demoTripTitle, Self.demoTripRegion)
        guard let demoTrips = try? context.fetch(request), !demoTrips.isEmpty else { return }
        for entity in demoTrips {
            if let id = entity.id { deleteTrip(id: id) }
        }
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
        Task { @MainActor in
            SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: tripId, action: .update))
        }
    }

    func updateTitle(for tripId: UUID, title: String) {
        repository.updateTitle(for: tripId, title: title)
        Task { @MainActor in
            SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: tripId, action: .update))
        }
    }

    func updateVehicle(for tripId: UUID, vehicleId: UUID?) {
        repository.updateVehicle(for: tripId, vehicleId: vehicleId)
        Task { @MainActor in
            SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: tripId, action: .update))
        }
    }

    /// Local-only, so no sync enqueue — see `updateCompanions` in the repo.
    ///
    /// NOTE: `CompanionsStore` — the actual writer of this cache after Task
    /// 7 — is a standalone `@MainActor` singleton with no reference to a
    /// `TripManager` instance (`TripManager` isn't a singleton; it's owned
    /// per-`MapViewModel`). It calls `TripRepository.updateCompanions`
    /// directly instead of through here, the same way `APISyncTransport`
    /// takes its own `TripRepository` rather than a `TripManager`. This
    /// method is kept for API parity with the rest of `TripManager`'s
    /// update* methods and as a stable entry point for any future caller
    /// that DOES hold a `TripManager`, but has no callers of its own today.
    func updateCompanions(for tripId: UUID, companions: [TripCompanion]) {
        repository.updateCompanions(for: tripId, companions: companions)
    }

    func updatePrivacy(for tripId: UUID, isPrivate: Bool) {
        repository.updatePrivacy(for: tripId, isPrivate: isPrivate)
    }

    /// Which of these trips this device holds a PRIVATE local row for.
    ///
    /// The feed asks before drawing: a trip taken private here is still served
    /// publicly by the server until the queued unpublish lands, and putting it
    /// back in front of the person who just hid it is the one thing that
    /// screen must not do.
    static func locallyPrivateTripIds(among ids: [UUID]) -> Set<UUID> {
        guard !ids.isEmpty else { return [] }
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "id IN %@ AND isPrivate == YES AND isDeleted == NO", ids
        )
        request.propertiesToFetch = ["id"]
        guard let rows = try? context.fetch(request) else { return [] }
        return Set(rows.compactMap { $0.id })
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
