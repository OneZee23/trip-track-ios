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

    static func loadPhoto(filename: String) -> UIImage? {
        let url = photosDirectory.appendingPathComponent(filename)
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

    /// Load a display-sized thumbnail (150pt max) with in-memory caching and efficient downsampling.
    @MainActor
    static func loadThumbnail(filename: String, maxSize: CGFloat = 150) async -> UIImage? {
        let key = filename as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }

        let scale = UIScreen.main.scale
        return await Task.detached(priority: .userInitiated) {
            let url = photosDirectory.appendingPathComponent(filename)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil as UIImage? }

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
            return thumbnail
        }.value
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
        let url = photosDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }
}
