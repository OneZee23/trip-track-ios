import Foundation
import CoreData
import OSLog

private let restoreLog = Logger(subsystem: "com.triptrack", category: "sync.vehiclePhotos")

/// Возвращает снимки машин на устройство (0.6.4).
///
/// Загрузка без выгрузки обратно была улицей с односторонним движением: файлы
/// уезжали в R2, каталог `Documents/VehiclePhotos/` исключён из резервной
/// копии — и на новом телефоне человек получал сетку серых плиток вместо
/// фотографий своей машины. При этом и журнал изменений, и все двенадцать
/// текстов магазина обещали, что снимки смену телефона переживают.
///
/// Работает по двум разным пустотам, и обе настоящие:
///  - **строки нет** — свежая установка, гараж приехал синком, а снимков в
///    базе нет вовсе;
///  - **строка есть, файла нет** — восстановление из резервной копии: CoreData
///    в неё попала, каталог со снимками нет.
///
/// Ничего не удаляет: снимок, которого нет на сервере, — это либо ещё не
/// уехавший локальный, либо снятый с публикации на другом устройстве, и
/// решать это здесь нельзя.
enum VehiclePhotoRestore {

    private struct Item: Decodable {
        let id: UUID
        let vehicleId: UUID
        let url: String?
        let thumbUrl: String?
        let isMain: Bool
        let takenAt: Date?
    }

    private struct Response: Decodable { let photos: [Item] }

    /// Вызывается после успешного пула, при включённой синхронизации.
    static func run(context: NSManagedObjectContext =
                    PersistenceController.shared.container.viewContext) async {
        let allowed = await MainActor.run {
            SettingsManager.shared.cloudSyncEnabled && AuthService.shared.isSignedIn
        }
        guard allowed else { return }

        let response: Response
        do {
            response = try await APIClient.shared.post(
                APIEndpoint.vehiclePhotoList, body: EmptyRequest())
        } catch {
            restoreLog.notice("список снимков не получен: \(String(describing: error), privacy: .public)")
            return
        }

        var restored = 0
        for item in response.photos {
            guard let source = item.url ?? item.thumbUrl,
                  let remote = URL(string: source) else { continue }

            let existing = row(id: item.id, context: context)
            let filename = (existing?.value(forKey: "filename") as? String)
                ?? (item.id.uuidString + ".jpg")
            let fileURL = VehiclePhotoStore.directory.appendingPathComponent(filename)
            let fileExists = FileManager.default.fileExists(atPath: fileURL.path)

            if existing != nil, fileExists { continue }

            if !fileExists {
                guard let data = try? await download(remote) else { continue }
                try? FileManager.default.createDirectory(
                    at: VehiclePhotoStore.directory, withIntermediateDirectories: true)
                guard (try? data.write(to: fileURL)) != nil else { continue }
                restored += 1
            }

            let entity = existing ?? NSEntityDescription.insertNewObject(
                forEntityName: "VehiclePhotoEntity", into: context)
            entity.setValue(item.id, forKey: "id")
            entity.setValue(item.vehicleId, forKey: "vehicleId")
            entity.setValue(filename, forKey: "filename")
            entity.setValue(item.isMain, forKey: "isMain")
            entity.setValue(item.takenAt ?? Date(), forKey: "timestamp")
            // Ключи в R2 сюда НЕ пишем: сервер прислал подписанные ссылки,
            // которые живут около часа, и записать их как ключ значило бы
            // сохранить мусор, по которому потом ничего не откроется.
            entity.setValue(SyncStatus.synced.rawValue, forKey: "syncStatus")
        }

        if context.hasChanges {
            try? context.save()
            restoreLog.notice("восстановлено снимков: \(restored, privacy: .public)")
        }
    }

    private static func row(id: UUID, context: NSManagedObjectContext) -> NSManagedObject? {
        let req = NSFetchRequest<NSManagedObject>(entityName: "VehiclePhotoEntity")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return (try? context.fetch(req))?.first
    }

    private static func download(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.invalidHTTPStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }
}
