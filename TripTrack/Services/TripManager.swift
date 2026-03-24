import Foundation
import CoreData
import Combine
import CoreLocation
import UIKit

final class TripManager: ObservableObject {
    @Published var activeTrip: Trip?
    @Published var isRecording = false

    var isPaused: Bool = false

    private let locationManager: LocationManager
    private let persistenceController: PersistenceController
    private var cancellables = Set<AnyCancellable>()
    private var activeTripEntity: TripEntity?
    private var lastLocation: CLLocation?
    private var unsavedPointCount = 0
    private var lastSaveTime = Date()
    private let saveBatchSize = 10
    private let saveInterval: TimeInterval = 15

    init(locationManager: LocationManager, persistenceController: PersistenceController = .shared) {
        self.locationManager = locationManager
        self.persistenceController = persistenceController

        locationManager.$currentLocation
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (update: LocationUpdate) in
                self?.handleNewLocation(update.toCLLocation())
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
        locationManager.startTracking()
    }

    @discardableResult
    func stopTrip() -> Trip? {
        locationManager.stopTracking()
        isRecording = false

        guard let entity = activeTripEntity else { return nil }
        entity.endDate = Date()
        updateEntityStats(entity)
        generatePreviewPolyline(for: entity)
        persistenceController.save()

        let completedTrip = tripFromEntity(entity)

        geocodeAndNameTrip(entity: entity)
        deleteDemoTripIfNeeded()

        activeTrip = nil
        activeTripEntity = nil
        lastLocation = nil

        return completedTrip
    }

    func fetchTrips() -> [Trip] {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "endDate != nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TripEntity.startDate, ascending: false)]
        request.fetchBatchSize = 25

        guard let entities = try? context.fetch(request) else { return [] }
        return entities.compactMap { tripFromEntity($0, includeTrackPoints: false) }
    }

    func fetchTripsWithTrackPoints() -> [Trip] {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "endDate != nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TripEntity.startDate, ascending: false)]

        guard let entities = try? context.fetch(request) else { return [] }
        return entities.compactMap { tripFromEntity($0) }
    }

    func fetchTripCount() -> Int {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "endDate != nil")
        return (try? context.count(for: request)) ?? 0
    }

    func fetchTotalDistance() -> Double {
        let context = persistenceController.container.viewContext
        let request = NSFetchRequest<NSDictionary>(entityName: "TripEntity")
        request.predicate = NSPredicate(format: "endDate != nil")
        request.resultType = .dictionaryResultType

        let sumDesc = NSExpressionDescription()
        sumDesc.name = "totalDistance"
        sumDesc.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "distance")])
        sumDesc.expressionResultType = .doubleAttributeType
        request.propertiesToFetch = [sumDesc]

        guard let results = try? context.fetch(request),
              let dict = results.first,
              let total = dict["totalDistance"] as? Double else { return 0 }
        return total
    }

    func deleteTrip(id: UUID) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        if let entity = try? context.fetch(request).first {
            PhotoStorageService.deletePhotos(for: id)
            context.delete(entity)
            persistenceController.save()
        }
    }

    func tripDetail(id: UUID) -> Trip? {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        guard let entity = try? context.fetch(request).first else { return nil }
        return tripFromEntity(entity)
    }

    // MARK: - Orphan Cleanup

    /// Called on init: finds trips with no endDate (app was killed mid-recording)
    /// and either deletes them (junk) or closes them using the last track point's timestamp.
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

            // Close the trip at the timestamp of the last recorded point
            let lastTimestamp = points.compactMap { $0.timestamp }.max() ?? Date()
            let actualDuration = max(0, entity.startDate.map { lastTimestamp.timeIntervalSince($0) } ?? 0)
            let isJunk = entity.distance < 500 && actualDuration < 120

            if isJunk {
                context.delete(entity)
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

        // Filter: reject poor accuracy
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= maxRecordAccuracy else { return }

        // Filter: minimum distance between stored points
        if let last = lastLocation {
            let delta = location.distance(from: last)
            guard delta >= minRecordDistance else { return }

            // Filter: GPS drift — device reports low speed but calculated distance is high
            let timeDelta = location.timestamp.timeIntervalSince(last.timestamp)
            if timeDelta > 0 {
                let calculatedSpeed = delta / timeDelta
                if location.speed < driftSpeedThreshold && calculatedSpeed > driftCalcSpeedLimit {
                    return
                }
            }
        }

        let context = persistenceController.container.viewContext
        let point = TrackPointEntity(context: context)
        point.id = UUID()
        point.latitude = location.coordinate.latitude
        point.longitude = location.coordinate.longitude
        point.altitude = location.altitude
        point.speed = max(0, location.speed)
        point.course = location.course
        point.horizontalAccuracy = location.horizontalAccuracy
        point.timestamp = location.timestamp
        point.trip = entity

        // Update distance
        if let last = lastLocation {
            let delta = location.distance(from: last)
            if delta < 1000 { // ignore jumps > 1km
                entity.distance += delta
            }
        }
        lastLocation = location

        // Update speeds
        let speed = max(0, location.speed)
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

    // MARK: - Geocoding

    private func geocodeAndNameTrip(entity: TripEntity) {
        guard let points = entity.trackPoints?.array as? [TrackPointEntity],
              let first = points.first, let last = points.last else { return }

        let startLoc = CLLocation(latitude: first.latitude, longitude: first.longitude)
        let endLoc = CLLocation(latitude: last.latitude, longitude: last.longitude)

        CLGeocoder().reverseGeocodeLocation(startLoc) { [weak self] startPMs, _ in
            let startName = Self.localityName(from: startPMs?.first)
            let startRegion = Self.regionName(from: startPMs?.first)

            // Circular route (< 20 km between start and finish)
            if startLoc.distance(from: endLoc) < 20_000 {
                Task { @MainActor [weak self] in
                    guard !entity.isDeleted else { return }
                    entity.title = startName ?? Self.dateFallbackTitle(for: entity.startDate)
                    entity.region = startRegion
                    self?.persistenceController.save()
                }
                return
            }

            // A → B route
            CLGeocoder().reverseGeocodeLocation(endLoc) { [weak self] endPMs, _ in
                let endName = Self.localityName(from: endPMs?.first)
                let title: String = switch (startName, endName) {
                case let (s?, e?): "\(s) → \(e)"
                case let (s?, nil): s
                case let (nil, e?): e
                case (nil, nil): Self.dateFallbackTitle(for: entity.startDate)
                }
                Task { @MainActor [weak self] in
                    guard !entity.isDeleted else { return }
                    entity.title = title
                    entity.region = startRegion
                    self?.persistenceController.save()
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

    /// Reverse-geocode only the region for an entity's first track point.
    private func geocodeRegion(for entity: TripEntity, completion: @escaping () -> Void) {
        guard !entity.isDeleted,
              let points = entity.trackPoints?.array as? [TrackPointEntity],
              let first = points.first else {
            completion()
            return
        }

        let location = CLLocation(latitude: first.latitude, longitude: first.longitude)
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            if let adminArea = placemarks?.first?.administrativeArea {
                Task { @MainActor [weak self] in
                    guard !entity.isDeleted else { return }
                    entity.region = adminArea
                    self?.persistenceController.save()
                }
            }
            completion()
        }
    }

    // MARK: - Region Migration

    /// Re-geocode region field for trips missing region data
    func migrateRegionsIfNeeded() {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "endDate != nil AND region == nil")

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

    private func deleteDemoTripIfNeeded() {
        guard let demoIdString = UserDefaults.standard.string(forKey: Self.demoTripIdKey),
              let demoId = UUID(uuidString: demoIdString) else { return }

        deleteTrip(id: demoId)
        UserDefaults.standard.removeObject(forKey: Self.demoTripIdKey)
    }

    // MARK: - Entity Conversion

    private func tripFromEntity(_ entity: TripEntity, includeTrackPoints: Bool = true) -> Trip? {
        guard let id = entity.id, let startDate = entity.startDate else { return nil }

        let points: [TrackPoint]
        if includeTrackPoints {
            points = (entity.trackPoints?.array as? [TrackPointEntity])?.compactMap { pe in
                guard let pid = pe.id, let ts = pe.timestamp else { return nil }
                return TrackPoint(
                    id: pid,
                    latitude: pe.latitude,
                    longitude: pe.longitude,
                    altitude: pe.altitude,
                    speed: pe.speed,
                    course: pe.course,
                    horizontalAccuracy: pe.horizontalAccuracy,
                    timestamp: ts
                )
            } ?? []
        } else {
            points = []
        }

        let photos: [TripPhoto] = (entity.photos?.array as? [TripPhotoEntity])?.compactMap { pe in
            guard let pid = pe.id, let filename = pe.filename, let ts = pe.timestamp else { return nil }
            return TripPhoto(id: pid, filename: filename, caption: pe.caption, timestamp: ts)
        } ?? []

        let badgeIds: [String]
        if let json = entity.badgesJSON,
           let data = json.data(using: .utf8),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            badgeIds = ids
        } else {
            badgeIds = []
        }

        return Trip(
            id: id,
            startDate: startDate,
            endDate: entity.endDate,
            distance: entity.distance,
            maxSpeed: entity.maxSpeed,
            averageSpeed: entity.averageSpeed,
            trackPoints: points,
            photos: photos,
            title: entity.title,
            tripDescription: entity.tripDescription,
            fuelUsed: entity.fuelUsed,
            elevation: entity.elevation,
            region: entity.region,
            isPrivate: entity.isPrivate,
            vehicleId: entity.vehicleId,
            previewPolyline: entity.previewPolyline,
            earnedBadgeIds: badgeIds
        )
    }

    // MARK: - Per-Trip Badges

    func saveBadgesJSON(tripId: UUID, badgeIds: [String]) {
        guard !badgeIds.isEmpty else { return }
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", tripId as CVarArg)
        if let entity = try? context.fetch(request).first {
            if let data = try? JSONEncoder().encode(badgeIds),
               let json = String(data: data, encoding: .utf8) {
                entity.badgesJSON = json
                persistenceController.save()
            }
        }
    }

    // MARK: - Preview Polyline

    /// Generate a simplified polyline (~20 points) for feed card previews.
    private func generatePreviewPolyline(for entity: TripEntity) {
        guard let points = entity.trackPoints?.array as? [TrackPointEntity],
              points.count >= 2 else { return }

        let coords = points.map {
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

    // MARK: - Photos

    func addPhoto(to tripId: UUID, image: UIImage, caption: String? = nil) -> TripPhoto? {
        guard let filename = PhotoStorageService.savePhoto(image, for: tripId) else { return nil }

        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", tripId as CVarArg)

        guard let entity = try? context.fetch(request).first else { return nil }

        let photoEntity = TripPhotoEntity(context: context)
        let photoId = UUID()
        photoEntity.id = photoId
        photoEntity.filename = filename
        photoEntity.caption = caption
        photoEntity.timestamp = Date()
        photoEntity.sortOrder = Int16(entity.photos?.count ?? 0)
        photoEntity.trip = entity

        persistenceController.save()

        return TripPhoto(id: photoId, filename: filename, caption: caption, timestamp: Date())
    }

    func deletePhoto(id: UUID, from tripId: UUID) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        if let entity = try? context.fetch(request).first {
            PhotoStorageService.deletePhoto(filename: entity.filename ?? "")
            context.delete(entity)
            persistenceController.save()
        }
    }

    func updateNotes(for tripId: UUID, notes: String) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", tripId as CVarArg)

        if let entity = try? context.fetch(request).first {
            entity.tripDescription = notes
            persistenceController.save()
        }
    }

    func updateTitle(for tripId: UUID, title: String) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", tripId as CVarArg)

        if let entity = try? context.fetch(request).first {
            entity.title = title.isEmpty ? nil : title
            persistenceController.save()
        }
    }

    // MARK: - Geocoding Retry

    func retryGeocodingForUntitledTrips() {
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
