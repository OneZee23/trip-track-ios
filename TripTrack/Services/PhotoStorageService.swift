import UIKit

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
            let diskURL = thumbnailDiskURL(for: filename)
            if let diskData = try? Data(contentsOf: diskURL),
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
            if let jpegData = thumbnail.jpegData(compressionQuality: 0.7) {
                let dir = diskURL.deletingLastPathComponent()
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? jpegData.write(to: diskURL)
            }

            return thumbnail
        }.value
    }

    /// Disk path for cached thumbnail: Documents/TripPhotos/{tripId}/.thumbnails/{photoFile}
    private static func thumbnailDiskURL(for filename: String) -> URL {
        let components = filename.split(separator: "/")
        guard components.count == 2 else {
            return photosDirectory.appendingPathComponent(".thumbnails/\(filename)")
        }
        let tripDir = String(components[0])
        let photoFile = String(components[1])
        return photosDirectory
            .appendingPathComponent(tripDir, isDirectory: true)
            .appendingPathComponent(".thumbnails", isDirectory: true)
            .appendingPathComponent(photoFile)
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
        let thumbURL = thumbnailDiskURL(for: filename)
        try? FileManager.default.removeItem(at: thumbURL)
        thumbnailCache.removeObject(forKey: filename as NSString)
    }
}
