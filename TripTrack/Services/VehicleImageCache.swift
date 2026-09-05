import UIKit
import ImageIO
import CryptoKit

/// Кэш картинок машины — общий для своих снимков и чужих.
///
/// Заведён из-за рывка при открытии карточки: картинка появлялась не сразу, а
/// через серый прямоугольник, и так на каждом заходе. Причин было две, и обе
/// настоящие:
///
/// 1. **Свои** снимки декодировались только в память. Перезапуск приложения —
///    и полноразмерный кадр с камеры разбирается заново, потому что копии
///    нужного размера нигде нет.
/// 2. **Чужие** грузились через `AsyncImage`, у которого своего кэша нет
///    вовсе. На проде ссылка подписанная и КАЖДЫЙ РАЗ НОВАЯ — совпадает только
///    путь, а запрос отличается, — поэтому и системный `URLCache` мимо: каждое
///    появление карточки означало новую загрузку по сети.
///
/// Отсюда устройство: чужой снимок один раз кладётся на диск и дальше живёт
/// ровно как свой, а ключ строится по ПУТИ ссылки без запроса, чтобы смена
/// подписи не сбрасывала кэш.
///
/// Три уровня: память (мгновенно, в том же кадре), диск (без сети и без
/// повторного разбора большого кадра), источник.
enum VehicleImageCache {

    // MARK: - Память

    private static let memory: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        // Не по числу картинок, а по их весу: десять миниатюр и десять
        // полноэкранных кадров — очень разные десятки.
        c.totalCostLimit = 48 * 1024 * 1024
        return c
    }()

    /// Готовая копия ИЗ ПАМЯТИ — синхронно, чтобы её можно было нарисовать в
    /// первом же кадре. Всё, что асинхронно, означает кадр с заглушкой.
    static func cached(_ key: String) -> UIImage? {
        memory.object(forKey: key as NSString)
    }

    /// Не `private`: тест проверяет, что память отвечает синхронно.
    static func remember(_ image: UIImage, _ key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memory.setObject(image, forKey: key as NSString, cost: cost)
    }

    // MARK: - Ключи

    /// Свой снимок: имя файла неизменяемо.
    static func localKey(_ filename: String, _ maxSize: CGFloat) -> String {
        "l:\(filename)@\(Int(maxSize))"
    }

    /// Чужой: только путь, БЕЗ запроса. Подпись в ссылке живёт час и меняется
    /// при каждом ответе сервера — с ней в ключе кэш не пережил бы ни одного
    /// обновления экрана.
    static func remoteKey(_ url: URL, _ maxSize: CGFloat) -> String {
        "r:\(url.path)@\(Int(maxSize))"
    }

    // MARK: - Диск

    private static var diskDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("VehicleImages", isDirectory: true)
    }

    /// Имя файла из ключа: ключи содержат путь и двоеточия, в имя их не
    /// положишь.
    private static func diskURL(_ key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.compactMap { String(format: "%02x", $0) }.joined()
        return diskDirectory.appendingPathComponent(name + ".jpg")
    }

    private static func readDisk(_ key: String) -> UIImage? {
        guard let data = try? Data(contentsOf: diskURL(key)),
              let image = UIImage(data: data) else { return nil }
        return image
    }

    private static func writeDisk(_ image: UIImage, _ key: String) {
        try? FileManager.default.createDirectory(
            at: diskDirectory, withIntermediateDirectories: true)
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: diskURL(key))
    }

    // MARK: - Уменьшенная копия из файла

    /// Копия нужного размера из файла на диске. Полный кадр не разворачивается
    /// в память: `CGImageSourceCreateThumbnailAtIndex` читает ровно столько,
    /// сколько нужно.
    static func sized(fileURL: URL, key: String, maxSize: CGFloat) async -> UIImage? {
        if let hit = cached(key) { return hit }
        let scale = await MainActor.run { UIScreen.main.scale }
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            if let fromDisk = readDisk(key) { return fromDisk }
            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: maxSize * scale,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { return nil }
            let made = UIImage(cgImage: cg)
            writeDisk(made, key)
            return made
        }.value
        if let image { remember(image, key) }
        return image
    }

    // MARK: - Чужой снимок

    /// Загрузить один раз и дальше обращаться как со своим.
    static func remote(_ url: URL, maxSize: CGFloat) async -> UIImage? {
        let key = remoteKey(url, maxSize)
        if let hit = cached(key) { return hit }
        if let fromDisk = await Task.detached(priority: .userInitiated, operation: {
            readDisk(key)
        }).value {
            remember(fromDisk, key)
            return fromDisk
        }
        // Оригинал кладём отдельным файлом — он же нужен другим размерам того
        // же снимка, и второй раз по сети за ним ходить незачем.
        let originalKey = "r:\(url.path)@original"
        let originalFile = diskURL(originalKey)
        if !FileManager.default.fileExists(atPath: originalFile.path) {
            guard let data = try? await download(url) else { return nil }
            try? FileManager.default.createDirectory(
                at: diskDirectory, withIntermediateDirectories: true)
            try? data.write(to: originalFile)
        }
        return await sized(fileURL: originalFile, key: key, maxSize: maxSize)
    }

    private static func download(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: - Уборка

    /// Снимок удалили — его копии всех размеров становятся мусором. Точечно
    /// вычистить нельзя (размеры заранее неизвестны), поэтому чистим память
    /// целиком и оставляем диск операционной системе: каталог кэшей она умеет
    /// подчищать сама.
    static func forget() {
        memory.removeAllObjects()
    }
}
