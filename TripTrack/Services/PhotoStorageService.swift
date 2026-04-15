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

        let photoFilename = UUID().uuidString + ".jpg"
        let fullPath = tripDir.appendingPathComponent(photoFilename)

        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        do {
            try data.write(to: fullPath)
            return tripId.uuidString + "/" + photoFilename
        } catch {
            return nil
        }
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

    // MARK: - Async Loading

    private static let thumbnailCache = NSCache<NSString, UIImage>()

    /// Load a photo asynchronously off the main thread.
    static func loadPhotoAsync(filename: String) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            loadPhoto(filename: filename)
        }.value
    }

    /// Load a display-sized thumbnail (150pt max) with two-tier caching:
    /// L1 = NSCache (in-memory), L2 = disk (.thumbnails/ subfolder).
    @MainActor
    static func loadThumbnail(filename: String, maxSize: CGFloat = 150) async -> UIImage? {
        let key = filename as NSString

        // L1: in-memory cache
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }

        let scale = UIScreen.main.scale
        return await Task.detached(priority: .userInitiated) {
            // L2: disk cache
            if let diskURL = thumbnailDiskURL(for: filename),
               let diskData = try? Data(contentsOf: diskURL),
               let diskImage = UIImage(data: diskData) {
                thumbnailCache.setObject(diskImage, forKey: key)
                return diskImage as UIImage?
            }

            // Generate from full photo
            guard let url = safePhotoURL(for: filename),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil as UIImage? }

            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: maxSize * scale,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
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

            return thumbnail
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
    }

    static func deletePhoto(filename: String) {
        guard let url = safePhotoURL(for: filename) else { return }
        try? FileManager.default.removeItem(at: url)
        // Clean up cached thumbnail (disk + memory)
        if let thumbURL = thumbnailDiskURL(for: filename) {
            try? FileManager.default.removeItem(at: thumbURL)
        }
        thumbnailCache.removeObject(forKey: filename as NSString)
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

    /// Read raw JPEG data for a photo (for upload to remote storage).
    static func photoData(filename: String) -> Data? {
        guard let url = safePhotoURL(for: filename) else { return nil }
        return try? Data(contentsOf: url)
    }
}
