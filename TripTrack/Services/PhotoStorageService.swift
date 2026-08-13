import UIKit
import CoreData

enum PhotoStorageService {
    private static var photosDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TripPhotos", isDirectory: true)
    }

    static func savePhoto(_ image: UIImage, for tripId: UUID) -> String? {
        let tripDir = photosDirectory.appendingPathComponent(tripId.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tripDir, withIntermediateDirectories: true)
        // Privacy-first: photos must not silently end up in iCloud / encrypted
        // device backup. The user's contract with us is "data stays on this
        // device unless Cloud Sync is enabled" — without `isExcludedFromBackup`
        // every photo gets uploaded into the user's iCloud backup, which is
        // recoverable from another device with their Apple ID. Set on the
        // photosDirectory root and on each tripDir as defense-in-depth (system
        // walks ancestors but the per-dir flag is the documented path).
        excludeFromBackupIfNeeded(photosDirectory)
        excludeFromBackupIfNeeded(tripDir)

        let photoFilename = UUID().uuidString + ".jpg"
        let fullPath = tripDir.appendingPathComponent(photoFilename)

        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        do {
            try data.write(to: fullPath)
            let relative = tripId.uuidString + "/" + photoFilename
            rememberExistence(true, for: relative)
            return relative
        } catch {
            return nil
        }
    }

    private static func excludeFromBackupIfNeeded(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Validate that a resolved path stays within photosDirectory (prevents path traversal).
    private static func safePhotoURL(for filename: String) -> URL? {
        let url = photosDirectory.appendingPathComponent(filename).standardizedFileURL
        guard url.path.hasPrefix(photosDirectory.standardizedFileURL.path) else { return nil }
        return url
    }

    static func loadPhoto(filename: String) -> UIImage? {
        guard let url = safePhotoURL(for: filename) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Existence

    /// A TripPhotoEntity row can outlive — or entirely predate — its file, so
    /// "the row says there is a photo" was never the same question as "there
    /// is a photo on this device". Two paths produce a row with no file:
    ///
    /// 1. `CoreDataTripRepository.applyRemotePhoto` writes a row straight from
    ///    `/sync/pull` metadata, `filename` included, and nothing anywhere
    ///    downloads the JPEG — `savePhoto` above is the only writer of photo
    ///    files in the whole app, and its one caller is `addPhoto`. A
    ///    reinstall or a second device therefore rebuilds every photo ROW and
    ///    zero photo FILES.
    /// 2. Restoring a device from an iCloud/iTunes backup does the same to a
    ///    single device: the CoreData store sits in Application Support and is
    ///    backed up, while `TripPhotos/` is deliberately marked
    ///    `isExcludedFromBackup` (see `savePhoto`) and is not.
    ///
    /// Cached because the photo strip asks once per body pass. A cached answer
    /// stays correct: filenames are freshly-minted UUIDs, so nothing but our
    /// own `savePhoto`/`deletePhoto` can change whether a given name resolves.
    private static let existenceLock = NSLock()
    private static var existenceCache: [String: Bool] = [:]

    static func localFileExists(filename: String) -> Bool {
        existenceLock.lock()
        let cached = existenceCache[filename]
        existenceLock.unlock()
        if let cached { return cached }

        guard let url = safePhotoURL(for: filename) else {
            rememberExistence(false, for: filename)
            return false
        }
        let exists = FileManager.default.fileExists(atPath: url.path)
        rememberExistence(exists, for: filename)
        return exists
    }

    private static func rememberExistence(_ exists: Bool, for filename: String) {
        existenceLock.lock()
        existenceCache[filename] = exists
        existenceLock.unlock()
    }

    private static func forgetAllExistence() {
        existenceLock.lock()
        existenceCache.removeAll()
        existenceLock.unlock()
    }

    // MARK: - Async Loading

    private static let thumbnailCache = NSCache<NSString, UIImage>()

    /// Load a photo asynchronously off the main thread.
    static func loadPhotoAsync(filename: String) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            loadPhoto(filename: filename)
        }.value
    }

    /// Why a thumbnail did not come back. `nil` collapsed "the file is gone
    /// for good" into "not loaded", which is how a dead row got to render as
    /// the same grey loading tile forever.
    enum ThumbnailOutcome {
        case image(UIImage)
        /// Nothing at that path. Permanent unless the row is repaired.
        case fileMissing
        /// The file is there but produced no image — a corrupt JPEG or a
        /// transient read error. NOT proof the photo is dead.
        case unreadable

        var image: UIImage? {
            if case .image(let image) = self { return image }
            return nil
        }
    }

    /// Load a display-sized thumbnail (150pt max) with two-tier caching:
    /// L1 = NSCache (in-memory), L2 = disk (.thumbnails/ subfolder).
    @MainActor
    static func loadThumbnail(filename: String, maxSize: CGFloat = 150) async -> UIImage? {
        await loadThumbnailOutcome(filename: filename, maxSize: maxSize).image
    }

    /// Same load, but says which of "no picture" it was.
    @MainActor
    static func loadThumbnailOutcome(filename: String, maxSize: CGFloat = 150) async -> ThumbnailOutcome {
        let key = filename as NSString

        // L1: in-memory cache
        if let cached = thumbnailCache.object(forKey: key) {
            return .image(cached)
        }

        let scale = UIScreen.main.scale
        return await Task.detached(priority: .userInitiated) { () -> ThumbnailOutcome in
            // L2: disk cache
            if let diskURL = thumbnailDiskURL(for: filename),
               let diskData = try? Data(contentsOf: diskURL),
               let diskImage = UIImage(data: diskData) {
                thumbnailCache.setObject(diskImage, forKey: key)
                return ThumbnailOutcome.image(diskImage)
            }

            // Ask the file system before ImageIO does. Handing
            // CGImageSourceCreateWithURL a path with nothing behind it is what
            // logged `IIOImageSource ... fileExists == false` on every pass,
            // and it answered with the same nil as a corrupt file — so the
            // caller could not tell a dead row from a bad read.
            guard let url = safePhotoURL(for: filename) else { return .fileMissing }
            guard localFileExists(filename: filename) else { return .fileMissing }

            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return .unreadable }

            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: maxSize * scale,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return .unreadable
            }

            let thumbnail = UIImage(cgImage: cgImage)
            thumbnailCache.setObject(thumbnail, forKey: key)

            // Write to disk cache for next launch
            if let jpegData = thumbnail.jpegData(compressionQuality: 0.7),
               let diskURL = thumbnailDiskURL(for: filename) {
                let dir = diskURL.deletingLastPathComponent()
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? jpegData.write(to: diskURL)
            }

            return .image(thumbnail)
        }.value
    }

    /// Disk path for cached thumbnail: Documents/TripPhotos/{tripId}/.thumbnails/{photoFile}
    private static func thumbnailDiskURL(for filename: String) -> URL? {
        let components = filename.split(separator: "/")
        let url: URL
        if components.count == 2 {
            let tripDir = String(components[0])
            let photoFile = String(components[1])
            url = photosDirectory
                .appendingPathComponent(tripDir, isDirectory: true)
                .appendingPathComponent(".thumbnails", isDirectory: true)
                .appendingPathComponent(photoFile)
        } else {
            url = photosDirectory.appendingPathComponent(".thumbnails/\(filename)")
        }
        let resolved = url.standardizedFileURL
        guard resolved.path.hasPrefix(photosDirectory.standardizedFileURL.path) else { return nil }
        return resolved
    }

    /// Clear thumbnail cache on memory warning.
    static func clearThumbnailCache() {
        thumbnailCache.removeAllObjects()
    }

    static func deletePhotos(for tripId: UUID) {
        let dir = photosDirectory.appendingPathComponent(tripId.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        // Whole-directory wipe: we never learn the individual names, so drop
        // every cached answer rather than keep stale `true`s for this trip.
        forgetAllExistence()
    }

    static func deletePhoto(filename: String) {
        guard let url = safePhotoURL(for: filename) else { return }
        try? FileManager.default.removeItem(at: url)
        // Clean up cached thumbnail (disk + memory)
        if let thumbURL = thumbnailDiskURL(for: filename) {
            try? FileManager.default.removeItem(at: thumbURL)
        }
        thumbnailCache.removeObject(forKey: filename as NSString)
        rememberExistence(false, for: filename)
    }

    // MARK: - Sync Support

    /// Fetch photos that need to be uploaded to the server.
    static func pendingUploads(persistenceController: PersistenceController = .shared) -> [(id: UUID, filename: String)] {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
        request.predicate = NSPredicate(format: "uploadStatus == %d", PhotoUploadStatus.localOnly.rawValue)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TripPhotoEntity.timestamp, ascending: true)]
        request.fetchBatchSize = 50

        guard let entities = try? context.fetch(request) else { return [] }
        return entities.compactMap { entity in
            guard let id = entity.id, let filename = entity.filename else { return nil }
            return (id: id, filename: filename)
        }
    }

    /// Mark a photo as uploaded with its remote URL.
    static func markUploaded(photoId: UUID, remoteURL: String, persistenceController: PersistenceController = .shared) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", photoId as CVarArg)
        request.fetchLimit = 1

        guard let entity = try? context.fetch(request).first else { return }
        entity.uploadStatus = PhotoUploadStatus.uploaded.rawValue
        entity.remoteURL = remoteURL
        persistenceController.save()
    }

    /// Fetch photo IDs that have a thumbnail but no remote URL yet (pending original upload).
    static func pendingOriginalUploads() -> [UUID] {
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
        req.predicate = NSPredicate(format: "thumbnailURL != nil AND remoteURL == nil")
        let results = (try? ctx.fetch(req)) ?? []
        return results.compactMap { $0.id }
    }

    /// Read raw JPEG data for a photo (for upload to remote storage).
    static func photoData(filename: String) -> Data? {
        guard let url = safePhotoURL(for: filename) else { return nil }
        return try? Data(contentsOf: url)
    }
}
