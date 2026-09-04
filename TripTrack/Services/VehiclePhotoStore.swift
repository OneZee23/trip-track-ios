import UIKit
import CoreData
import ImageIO

/// Фотографии машины: файлы на диске, строки в CoreData, одна «главная».
///
/// Своё хранилище, а не переиспользование `PhotoStorageService`: то живёт в
/// `Documents/TripPhotos/<tripId>/` и стирается вместе с поездкой, а эти
/// принадлежат машине и обязаны пережить удаление любой её поездки.
///
/// Каталог помечен `isExcludedFromBackup` по той же причине, что и фото
/// поездок: договор с человеком — «данные не покидают устройство, пока не
/// включена синхронизация», а необлагороженный каталог уезжает в iCloud-бэкап
/// и достаётся оттуда с любого другого устройства по тому же Apple ID.
enum VehiclePhotoStore {

    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VehiclePhotos", isDirectory: true)
    }

    // MARK: - Чтение

    /// Снимки машины: главная первой, остальные по времени добавления.
    static func photos(of vehicleId: UUID,
                       context: NSManagedObjectContext = PersistenceController.shared.container.viewContext)
    -> [VehiclePhoto] {
        let req = NSFetchRequest<NSManagedObject>(entityName: "VehiclePhotoEntity")
        req.predicate = NSPredicate(format: "vehicleId == %@", vehicleId as CVarArg)
        guard let rows = try? context.fetch(req) else { return [] }
        // Строка без файла — «надгробие». Так выглядит гараж после смены
        // телефона: CoreData уезжает в бэкап, а каталог со снимками помечен
        // как исключённый из него, — и человек видит сетку серых плиток с
        // надписью «главная», которые нечем ни открыть, ни убрать иначе как
        // по одной. Чистим при чтении, а не показываем пустоту с подписью.
        let alive = rows.compactMap(VehiclePhoto.init(entity:)).filter { photo in
            let exists = FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(photo.filename).path)
            if !exists, photo.remoteURL == nil {
                // Серверной копии тоже нет — восстанавливать нечего.
                if let row = rows.first(where: { ($0.value(forKey: "id") as? UUID) == photo.id }) {
                    context.delete(row)
                }
            }
            return exists || photo.remoteURL != nil
        }
        if context.hasChanges { try? context.save() }
        return alive
            .sorted { a, b in
                if a.isMain != b.isMain { return a.isMain }
                return a.timestamp < b.timestamp
            }
    }

    static func mainPhoto(of vehicleId: UUID) -> VehiclePhoto? {
        photos(of: vehicleId).first
    }

    /// Уменьшенная копия снимка — то, что нужно показать почти везде.
    ///
    /// Фотографии пишутся с камеры (десяток мегапикселей), а показываются
    /// плитками по сто точек. Раньше каждая плитка декодировала ОРИГИНАЛ, и
    /// делала это прямо в теле вью — то есть заново на каждую перерисовку,
    /// включая анимацию диалога. На экране, который существует ради того,
    /// чтобы держать много снимков, это подвисания и реальный шанс быть
    /// убитым по памяти на старом телефоне.
    ///
    /// Кэш в памяти, потому что ключ — имя файла, а файл неизменяем: снимок
    /// либо есть, либо удалён вместе со строкой.
    private static let thumbCache = NSCache<NSString, UIImage>()

    static func thumbnail(_ photo: VehiclePhoto, maxSize: CGFloat) async -> UIImage? {
        let key = "\(photo.filename)@\(Int(maxSize))" as NSString
        if let cached = thumbCache.object(forKey: key) { return cached }
        let url = directory.appendingPathComponent(photo.filename)
        let scale = await MainActor.run { UIScreen.main.scale }
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: maxSize * scale,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { return nil }
            let image = UIImage(cgImage: cg)
            thumbCache.setObject(image, forKey: key)
            return image
        }.value
    }

    /// Полный размер — только там, где снимок действительно смотрят целиком.
    static func image(_ photo: VehiclePhoto) -> UIImage? {
        UIImage(contentsOfFile: directory.appendingPathComponent(photo.filename).path)
    }

    // MARK: - Запись

    @discardableResult
    static func add(_ image: UIImage, to vehicleId: UUID,
                    sourceTripId: UUID? = nil,
                    context: NSManagedObjectContext = PersistenceController.shared.container.viewContext)
    -> VehiclePhoto? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        excludeFromBackup(directory)

        let filename = UUID().uuidString + ".jpg"
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        do {
            try data.write(to: directory.appendingPathComponent(filename))
        } catch {
            return nil
        }

        let isFirst = photos(of: vehicleId, context: context).isEmpty
        let e = NSEntityDescription.insertNewObject(forEntityName: "VehiclePhotoEntity", into: context)
        let id = UUID()
        e.setValue(id, forKey: "id")
        e.setValue(vehicleId, forKey: "vehicleId")
        e.setValue(filename, forKey: "filename")
        // Первый снимок становится главной сам: у машины должно быть лицо, и
        // заставлять человека назначать его отдельным действием, когда выбора
        // всё равно нет, — лишний шаг ради формальности.
        e.setValue(isFirst, forKey: "isMain")
        e.setValue(Date(), forKey: "timestamp")
        e.setValue(Date(), forKey: "lastModifiedAt")
        if let sourceTripId { e.setValue(sourceTripId, forKey: "sourceTripId") }
        try? context.save()
        // Снимок уходит на сервер только при включённой синхронизации — это
        // проверяет сама очередь (`SyncEnqueuer` держит фотографии машины в
        // одной корзине с самой машиной, то есть с личными данными).
        // Без этой строки снимки жили ТОЛЬКО на телефоне: каталог исключён из
        // бэкапа, и смена устройства стирала их насовсем.
        enqueue(id, action: .upload)
        return VehiclePhoto(id: id, vehicleId: vehicleId, filename: filename,
                            isMain: isFirst, timestamp: Date(), sourceTripId: sourceTripId)
    }

    /// Поставить операцию в очередь синхронизации.
    ///
    /// Пропустит её только включённая синхронизация: фотография машины —
    /// личные данные, как и сама машина, и уезжать без спроса не должна.
    private static func enqueue(_ photoId: UUID, action: SyncOperation.Action) {
        Task { @MainActor in
            SyncEnqueuer.enqueue(SyncOperation(entityType: .vehiclePhoto,
                                               entityId: photoId, action: action))
        }
    }

    static func makeMain(_ photoId: UUID, of vehicleId: UUID,
                         context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        let req = NSFetchRequest<NSManagedObject>(entityName: "VehiclePhotoEntity")
        req.predicate = NSPredicate(format: "vehicleId == %@", vehicleId as CVarArg)
        guard let rows = try? context.fetch(req) else { return }
        for row in rows {
            let isTarget = (row.value(forKey: "id") as? UUID) == photoId
            row.setValue(isTarget, forKey: "isMain")
            if isTarget {
                row.setValue(Date(), forKey: "lastModifiedAt")
                // Главная — часть того, как машина выглядит у других, поэтому
                // смена лица обязана доехать до сервера, а не остаться местной.
                enqueue(photoId, action: .update)
            }
        }
        try? context.save()
    }

    /// Удаляет и строку, и ФАЙЛ. Каскад CoreData файлов не трогает — забыть
    /// про них значит оставить снимки на устройстве навсегда.
    static func delete(_ photoId: UUID, of vehicleId: UUID,
                       context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        let req = NSFetchRequest<NSManagedObject>(entityName: "VehiclePhotoEntity")
        req.predicate = NSPredicate(format: "id == %@", photoId as CVarArg)
        guard let row = (try? context.fetch(req))?.first else { return }
        let wasMain = (row.value(forKey: "isMain") as? Bool) ?? false
        let hadServerCopy = row.value(forKey: "remoteURL") != nil
            || row.value(forKey: "thumbnailURL") != nil
        if let name = row.value(forKey: "filename") as? String {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        context.delete(row)
        try? context.save()
        // Удалять на сервере есть смысл только если он там что-то видел.
        // Строку удаляем ДО постановки в очередь, поэтому решение принимается
        // здесь, по снятому заранее флагу, — потом спросить будет не у кого.
        if hadServerCopy { enqueue(photoId, action: .delete) }

        // Машина не остаётся безлицой: главной становится следующая по времени.
        if wasMain, let next = photos(of: vehicleId, context: context).first {
            makeMain(next.id, of: vehicleId, context: context)
        }
    }

    /// Стереть все снимки машины — для удаления машины и для удаления аккаунта.
    static func deleteAll(of vehicleId: UUID,
                          context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        for photo in photos(of: vehicleId, context: context) {
            delete(photo.id, of: vehicleId, context: context)
        }
    }

    private static func excludeFromBackup(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}

/// Снимок машины. Отдельно от `TripPhoto`: у того есть подпись и связь с
/// поездкой, у этого — «главная» и ссылка на поездку-ИСТОЧНИК (подпись под
/// снимком берётся из неё, а не набирается руками).
struct VehiclePhoto: Identifiable, Hashable {
    let id: UUID
    let vehicleId: UUID
    let filename: String
    let isMain: Bool
    let timestamp: Date
    let sourceTripId: UUID?
    /// Ключ в R2, если снимок уже уехал на сервер. Отличает «файл потерян
    /// насовсем» от «файл потерян, но копия есть».
    let remoteURL: String?

    init(id: UUID, vehicleId: UUID, filename: String, isMain: Bool,
         timestamp: Date, sourceTripId: UUID?, remoteURL: String? = nil) {
        self.id = id
        self.vehicleId = vehicleId
        self.filename = filename
        self.isMain = isMain
        self.timestamp = timestamp
        self.sourceTripId = sourceTripId
        self.remoteURL = remoteURL
    }

    init?(entity: NSManagedObject) {
        guard let id = entity.value(forKey: "id") as? UUID,
              let vehicleId = entity.value(forKey: "vehicleId") as? UUID,
              let filename = entity.value(forKey: "filename") as? String,
              let timestamp = entity.value(forKey: "timestamp") as? Date
        else { return nil }
        self.id = id
        self.vehicleId = vehicleId
        self.filename = filename
        self.isMain = (entity.value(forKey: "isMain") as? Bool) ?? false
        self.timestamp = timestamp
        self.sourceTripId = entity.value(forKey: "sourceTripId") as? UUID
        self.remoteURL = entity.value(forKey: "remoteURL") as? String
    }
}
