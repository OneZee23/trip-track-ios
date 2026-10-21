import Foundation
import OSLog

private let catalogsLog = Logger(subsystem: "com.triptrack", category: "remotecatalogs")

/// Каталоги, которые меняются без новой версии (0.9.0): загадки и машины.
///
/// Сервер отдаёт тот же JSON, что лежит в бандле, целиком, с хешем версии
/// (`GET /app/catalog/<name>`). Телефон кладёт его в Application Support, а
/// каталог при следующей загрузке берёт его вместо бандлового
/// (`RemoteCatalogs.fileURL(for:)`). Разбор у каталогов прежний — меняется
/// только источник файла; файл, который не разобрался, каталог отбрасывает и
/// берёт бандл, так что сломанный ответ сервера не оставит человека без
/// каталога.
///
/// Свежий файл действует со СЛЕДУЮЩЕГО запуска: каталоги собираются один раз
/// на процесс (`VehicleCatalog.makes`, `BundleRiddleCatalog.shared`), и
/// подменять их на ходу значило бы переделывать всё, что их держит.
enum RemoteCatalogs {
    enum Name: String, CaseIterable { case riddles, vehicles }

    static let refreshInterval: TimeInterval = 24 * 60 * 60

    struct Response: Decodable {
        let version: String
        let unchanged: Bool?
        /// Сам каталог как есть — его разбирает каталог, а не мы.
        let catalog: AnyJSON?
    }

    /// Свежий файл каталога с сервера, если он есть.
    static func fileURL(for name: Name) -> URL? {
        let url = directory().appendingPathComponent("\(name.rawValue).json")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("remote-catalogs", isDirectory: true)
    }

    /// Раз в сутки на каталог; ошибка сети ничего не трогает.
    static func refreshIfNeeded(now: Date = Date(), defaults: UserDefaults = .standard) async {
        for name in Name.allCases {
            let dateKey = "remoteCatalog.\(name.rawValue).refreshedAt"
            let versionKey = "remoteCatalog.\(name.rawValue).version"
            if let last = defaults.object(forKey: dateKey) as? Date,
               now.timeIntervalSince(last) < refreshInterval, fileURL(for: name) != nil { continue }
            let known = fileURL(for: name) == nil ? nil : defaults.string(forKey: versionKey)
            do {
                let client = await MainActor.run { APIClient.shared }
                let response: Response = try await client.get(
                    APIEndpoint.remoteCatalog(name.rawValue, version: known), requiresAuth: false)
                if response.unchanged == true {
                    defaults.set(now, forKey: dateKey)
                    continue
                }
                guard let catalog = response.catalog else { continue }
                let data = try JSONEncoder().encode(catalog)
                try FileManager.default.createDirectory(at: directory(), withIntermediateDirectories: true)
                try data.write(to: directory().appendingPathComponent("\(name.rawValue).json"), options: .atomic)
                defaults.set(response.version, forKey: versionKey)
                defaults.set(now, forKey: dateKey)
                catalogsLog.notice("catalog \(name.rawValue, privacy: .public) updated (\(data.count, privacy: .public) bytes)")
            } catch {
                catalogsLog.notice("catalog \(name.rawValue, privacy: .public) refresh skipped")
            }
        }
    }
}

/// Произвольный JSON без схемы — каталог мы только сохраняем, не читаем.
enum AnyJSON: Codable, Equatable {
    case object([String: AnyJSON]), array([AnyJSON]), string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([AnyJSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: AnyJSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v):
            // Целые — целыми: каталог машин держит `version: 1`, а не 1.0.
            if v.rounded() == v, abs(v) < 1e15 { try c.encode(Int64(v)) } else { try c.encode(v) }
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}
