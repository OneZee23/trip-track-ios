#if DEBUG && targetEnvironment(simulator)
import CoreData
import UIKit

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
        request.predicate = NSPredicate(format: "endDate != nil")
        request.fetchLimit = 2
        let trips = (try? context.fetch(request)) ?? []
        for trip in trips { trip.isPrivate = false }
        PersistenceController.shared.save()
        StatsCache.invalidate()
        settings.profileBio = "Езжу за новыми историями и красивыми дорогами"
        for trip in trips {
            if let id = trip.id, !settings.pinnedTripIds.contains(id) { settings.togglePinnedTrip(id) }
        }
        if ProfilePhotoStore.shared.photos.isEmpty {
            for index in 0..<4 {
                if let data = image(index) { try? await ProfilePhotoStore.shared.add(data) }
            }
        }
        NotificationCenter.default.post(name: .syncPullCompleted, object: nil)
    }
}
#endif
