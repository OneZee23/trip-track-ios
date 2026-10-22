import Foundation
import Combine
import OSLog

@MainActor
final class ProfilePhotoStore: ObservableObject {
    static let shared = ProfilePhotoStore()
    static let limit = 9
    static let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ProfilePhotos", isDirectory: true)

    struct Photo: Codable, Identifiable, Equatable {
        let id: UUID
        var order: Int
        var takenAt: Date?
        var filename: String?
        var thumbnailUploaded = false
        var originalUploaded = false
        var thumbnailKey: String?
        var originalKey: String?
        var thumbnailURL: String?
        var originalURL: String?
    }
    private struct Metadata: Codable {
        var photos: [Photo] = []
        var deletions: [UUID] = []
        var removed: [UUID] = []
        var orderDirty = false
    }
    private struct PhotoList: Decodable { let photos: [ProfilePhotoDTO] }
    private struct DeleteRequest: Encodable { let photoId: String }
    private struct OrderRequest: Encodable { let photoIds: [String] }
    enum StoreError: Error { case limitReached, invalidImage }

    @Published private(set) var photos: [Photo] = []
    @Published var limitReached = false
    private let directory: URL
    private var metadata = Metadata()
    private var generation = UUID()
    private var mutationRevision = 0
    /// Moves whenever a photo is added or one of its variants is confirmed
    /// uploaded. A server snapshot requested before such a change may lack
    /// that photo, and must not be read as «deleted on another phone».
    private(set) var uploadRevision = 0
    /// The account session the store belongs to; a sign-out or wipe replaces
    /// it. Imports capture it before their first await.
    var session: UUID { generation }
    private var syncing = false
    private let syncEnabled: Bool
    private let log = Logger(subsystem: "com.triptrack", category: "profile.photos")

    init(directory: URL = ProfilePhotoStore.directory, syncEnabled: Bool = true) {
        self.directory = directory
        self.syncEnabled = syncEnabled
        if let data = try? Data(contentsOf: directory.appendingPathComponent("metadata.json")),
           let saved = try? JSONDecoder().decode(Metadata.self, from: data) {
            metadata = saved
            photos = saved.photos.sorted { $0.order < $1.order }
        }
    }

    func fileURL(_ photo: Photo) -> URL? {
        photo.filename.map { directory.appendingPathComponent($0) }
    }

    @discardableResult
    func add(_ data: Data, takenAt: Date? = nil, session: UUID? = nil) async throws -> UUID {
        // An import that began under another account (sign-out while the
        // picker was still loading) must not land in this one.
        if let session, session != generation { throw CancellationError() }
        guard photos.count < Self.limit else { throw StoreError.limitReached }
        let epoch = generation
        guard let prepared = await APISyncTransport.encodePhotoVariants(
            originalData: data, makeThumbnail: false, makeOriginal: true),
              let jpeg = prepared.original else { throw StoreError.invalidImage }
        guard generation == epoch else { throw CancellationError() }
        // Encoding yields; another picker task may have filled the last slot.
        guard photos.count < Self.limit else { throw StoreError.limitReached }
        try prepareDirectory()
        let id = UUID()
        let filename = "profile-" + id.uuidString.lowercased() + ".jpg"
        try jpeg.write(to: directory.appendingPathComponent(filename), options: .atomic)
        photos.append(Photo(id: id, order: photos.count, takenAt: takenAt, filename: filename))
        metadata.orderDirty = true
        mutationRevision &+= 1
        uploadRevision &+= 1
        save()
        Task { await sync() }
        return id
    }

    func delete(_ id: UUID) {
        guard let photo = photos.first(where: { $0.id == id }) else { return }
        if let url = fileURL(photo) { try? FileManager.default.removeItem(at: url) }
        photos.removeAll { $0.id == id }
        if !metadata.deletions.contains(id) { metadata.deletions.append(id) }
        if !metadata.removed.contains(id) { metadata.removed.append(id) }
        metadata.orderDirty = true
        mutationRevision &+= 1
        save()
        Task { await sync() }
    }

    func makeFirst(_ id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }), index != 0 else { return }
        let photo = photos.remove(at: index)
        photos.insert(photo, at: 0)
        metadata.orderDirty = true
        mutationRevision &+= 1
        // A reorder also makes older snapshots stale: once the server has
        // acknowledged it, a late `/auth/me` from before would put the old
        // order back.
        uploadRevision &+= 1
        save()
        Task { await sync() }
    }

    /// `revision` — `uploadRevision` read when the snapshot was REQUESTED.
    /// Only a snapshot taken after the last local upload may remove photos or
    /// reorder them; an older one can only add what this phone lacks.
    func restore(_ remote: [ProfilePhotoDTO]?, revision: Int? = nil) {
        guard let remote else { return }
        let fresh = revision == uploadRevision
        if fresh {
            // A photo this phone finished uploading but the server no longer
            // lists was deleted on another phone: the server's answer wins.
            let remoteIds = Set(remote.map(\.id))
            // Also a photo with no file here: it only ever came from the
            // server, so the server not listing it is the whole answer.
            func gone(_ photo: Photo) -> Bool {
                !remoteIds.contains(photo.id)
                    && (photo.filename == nil || (photo.thumbnailUploaded && photo.originalUploaded))
            }
            for photo in photos where gone(photo) {
                if let url = fileURL(photo) { try? FileManager.default.removeItem(at: url) }
            }
            photos.removeAll(where: gone)
        }
        for item in remote where !metadata.removed.contains(item.id) {
            if let index = photos.firstIndex(where: { $0.id == item.id }) {
                photos[index].thumbnailURL = item.thumbnailUrl
                photos[index].originalURL = item.originalUrl
                // The server only ever gains variants; never unset a flag here.
                if item.thumbnailUrl != nil { photos[index].thumbnailUploaded = true }
                if item.originalUrl != nil { photos[index].originalUploaded = true }
            } else if photos.count < Self.limit {
                photos.append(Photo(id: item.id, order: photos.count,
                                    takenAt: item.takenAt.flatMap(ISODate.parse), filename: nil,
                                    thumbnailUploaded: item.thumbnailUrl != nil,
                                    originalUploaded: item.originalUrl != nil,
                                    thumbnailURL: item.thumbnailUrl, originalURL: item.originalUrl))
            }
        }
        if fresh, !metadata.orderDirty {
            let positions = Dictionary(remote.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
            photos.sort { (positions[$0.id] ?? Int.max) < (positions[$1.id] ?? Int.max) }
        }
        save()
    }

    /// Anything this phone still owes the server. `sync()` runs on every
    /// sync pass, and without this gate each pass would cost a list request.
    var hasPendingWork: Bool {
        !metadata.deletions.isEmpty || metadata.orderDirty
            || photos.contains { $0.filename != nil && (!$0.thumbnailUploaded || !$0.originalUploaded) }
    }

    func sync() async {
        guard syncEnabled, !syncing, hasPendingWork, AuthService.shared.isSignedIn,
              let account = TokenStore.shared.accountId else { return }
        syncing = true
        let epoch = generation
        let revision = mutationRevision
        defer {
            if epoch == generation {
                syncing = false
                if revision != mutationRevision { Task { await sync() } }
            }
        }
        func isCurrent() -> Bool {
            epoch == generation && AuthService.shared.isSignedIn && TokenStore.shared.accountId == account
        }
        do {
            for id in metadata.deletions {
                let _: EmptyResponse = try await APIClient.shared.post(
                    APIEndpoint.profilePhotoDelete, body: DeleteRequest(photoId: id.uuidString.lowercased()))
                guard isCurrent() else { return }
                metadata.deletions.removeAll { $0 == id }
                save()
            }
            let listRevision = uploadRevision
            let list: PhotoList = try await APIClient.shared.post(APIEndpoint.profilePhotoList, body: EmptyRequest())
            guard isCurrent() else { return }
            restore(list.photos, revision: listRevision)
            for photo in photos where !photo.thumbnailUploaded || !photo.originalUploaded {
                guard let url = fileURL(photo) else { continue }
                let data = try await Task.detached(priority: .utility) { try Data(contentsOf: url) }.value
                guard let variants = await APISyncTransport.encodePhotoVariants(
                    originalData: data, makeThumbnail: !photo.thumbnailUploaded,
                    makeOriginal: !photo.originalUploaded) else { continue }
                for (type, bytes) in [(PhotoType.thumbnail, variants.thumbnail), (.original, variants.original)] {
                    guard isCurrent(), photos.contains(where: { $0.id == photo.id }) else { return }
                    guard let bytes else { continue }
                    let response = try await R2PhotoStorage.shared.uploadProfilePhotoPart(
                        photoId: photo.id, type: type, data: bytes, takenAt: photo.takenAt)
                    guard isCurrent() else { return }
                    guard let index = photos.firstIndex(where: { $0.id == photo.id }) else { continue }
                    uploadRevision &+= 1
                    if type == .thumbnail {
                        photos[index].thumbnailUploaded = true
                        photos[index].thumbnailKey = response.url
                    } else {
                        photos[index].originalUploaded = true
                        photos[index].originalKey = response.url
                    }
                    save()
                }
            }
            if metadata.orderDirty {
                let ids = photos.map(\.id)
                let _: EmptyResponse = try await APIClient.shared.post(
                    APIEndpoint.profilePhotoOrder,
                    body: OrderRequest(photoIds: ids.map { $0.uuidString.lowercased() }))
                guard isCurrent() else { return }
                if ids == photos.map(\.id) { metadata.orderDirty = false; save() }
            }
        } catch {
            guard isCurrent() else { return }
            if case APIError.unknownServer(let code, _) = error, code == "PROFILE_PHOTO_LIMIT" {
                limitReached = true
            }
            log.error("profile photo sync failed: \(error.localizedDescription)")
        }
    }

    #if DEBUG
    /// What a successful `/profile/photos/order` does to local state, for the
    /// stale-snapshot test (the store under test has sync disabled).
    func acknowledgeOrderForTesting() { metadata.orderDirty = false; save() }
    #endif

    func wipe() {
        generation = UUID()
        syncing = false
        photos = []
        metadata = Metadata()
        limitReached = false
        try? FileManager.default.removeItem(at: directory)
        VehicleImageCache.purgeDisk()
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private func save() {
        for index in photos.indices { photos[index].order = index }
        metadata.photos = photos
        do {
            try prepareDirectory()
            try JSONEncoder().encode(metadata).write(to: directory.appendingPathComponent("metadata.json"), options: .atomic)
        } catch { log.error("profile photo metadata save failed: \(error.localizedDescription)") }
    }
}
