#if DEBUG && targetEnvironment(simulator)
import CoreData
import UIKit
import CoreLocation

enum DebugProfileCardSeed {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-seed-profile-card") }

    static func image(_ index: Int) -> Data? {
        let colors: [UIColor] = [.systemTeal, .systemOrange, .systemIndigo, .systemGreen, .systemPink]
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 480, height: 480), format: format).image { context in
            colors[index % colors.count].setFill()
            context.fill(CGRect(x: 0, y: 0, width: 480, height: 480))
        }.jpegData(compressionQuality: 0.7)
    }

    @MainActor static func run() async {
        let settings = SettingsManager.shared
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]
        request.predicate = NSPredicate(format: "endDate != nil AND NOT (title IN %@)", ["На работу", "По городу"])
        request.fetchLimit = 2
        let trips = (try? context.fetch(request)) ?? []
        for trip in trips { trip.isPrivate = false }
        PersistenceController.shared.save()
        StatsCache.invalidate()
        settings.profileBio = "Езжу за новыми историями и красивыми дорогами"
        for trip in trips {
            if let id = trip.id, !settings.pinnedTripIds.contains(id) { settings.togglePinnedTrip(id) }
        }
        if ProcessInfo.processInfo.arguments.contains("-seed-profile-no-cover") {
            ProfilePhotoStore.shared.wipe()
            // Чистое состояние приглашения: прошлый прогон мог его скрыть.
            UserDefaults.standard.removeObject(forKey: ProfileCoverPrompt.hiddenKey)
        } else if ProfilePhotoStore.shared.photos.isEmpty {
            for index in 0..<4 {
                if let data = image(index) { try? await ProfilePhotoStore.shared.add(data) }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-seed-profile-journal") {
            seedRoutine(context: context)
            PersistenceController.shared.save()
            StatsCache.invalidate()
        }
        NotificationCenter.default.post(name: .syncPullCompleted, object: nil)
    }
    @MainActor private static func seedRoutine(context: NSManagedObjectContext) {
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        let ids = (0..<10).compactMap { index in
            UUID(uuidString: "09100000-0000-4000-8000-" + String(format: "%012d", index))
        }
        request.predicate = NSPredicate(format: "id IN %@", ids)
        let existing = Set(((try? context.fetch(request)) ?? []).compactMap(\.id))
        let calendar = Calendar.current
        let startOfMonth = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        for (index, id) in ids.enumerated() where !existing.contains(id) {
            let trip = TripEntity(context: context)
            trip.id = id
            // Stay in this month even when the test runs near its beginning.
            let start = max(startOfMonth.addingTimeInterval(1), Date().addingTimeInterval(-Double(index + 1) * 600))
            trip.startDate = start
            trip.endDate = start.addingTimeInterval(300)
            trip.title = index.isMultiple(of: 2) ? "На работу" : "По городу"
            trip.titleIsCustom = true
            trip.region = "Krasnodar Krai"
            trip.distance = 5_000
            trip.averageSpeed = 16.7
            trip.maxSpeed = 20
            trip.isPrivate = true
            trip.isTrackProcessed = true
            trip.roadFillState = RoadFillState.done.rawValue
            trip.previewPolyline = Trip.encodePolyline([
                CLLocationCoordinate2D(latitude: 45.05, longitude: 39.02),
                CLLocationCoordinate2D(latitude: 45.07, longitude: 39.07)])
        }
    }
}
#endif
