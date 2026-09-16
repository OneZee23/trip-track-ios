import Foundation

/// Каталог секретов с сервера: `{version, salt, secrets}` или `{version, unchanged}`.
///
/// Разбирается МЯГКО, и это главное решение этого файла. Каталог — единственный
/// ответ сервера, который приложение спрашивает вообще всегда (он публичный, без
/// аккаунта и без Cloud Sync), и упасть на разборе он не имеет права: символ,
/// которого не знает эта сборка, — это будущая гравюра волны 5, а не повод
/// остаться без каталога до следующего релиза. Поэтому `symbol` приезжает
/// строкой и превращается в `SealSymbol` с запасным вариантом, а `polygon`
/// умеет отсутствовать.
struct SecretCatalogResponse: Decodable {
    let version: String
    /// Есть только в полном ответе: соль без списка означала бы «соль новая,
    /// хеши старые», и сервер её в `unchanged` не кладёт нарочно.
    let salt: String?
    let unchanged: Bool?
    let secrets: [SecretRecord]?

    private enum CodingKeys: String, CodingKey {
        case version, salt, unchanged, secrets
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(String.self, forKey: .version)
        salt = try c.decodeIfPresent(String.self, forKey: .salt)
        unchanged = try c.decodeIfPresent(Bool.self, forKey: .unchanged)
        secrets = try c.decodeIfPresent([Entry].self, forKey: .secrets)?.map(\.record)
    }

    /// Запись каталога «как на проводе». Отдельно от `SecretRecord`, потому что
    /// на проводе символ — строка, а `SealSymbol` — закрытый набор этой сборки.
    private struct Entry: Decodable {
        let record: SecretRecord

        private enum CodingKeys: String, CodingKey {
            case id, hashes, reach, symbol, polygon
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
                .flatMap(SealSymbol.init(rawValue:)) ?? .generic
            record = SecretRecord(
                id: try c.decode(String.self, forKey: .id),
                hashes: try c.decode([UInt32].self, forKey: .hashes),
                reach: try c.decodeIfPresent(Double.self, forKey: .reach) ?? 0,
                symbol: symbol,
                polygon: try c.decodeIfPresent(Bool.self, forKey: .polygon) ?? false
            )
        }
    }

    /// Полный ответ — это ответ, в котором есть и соль, и список. `unchanged`
    /// спрашивается отдельно, потому что «версия та же» и «список пуст» —
    /// разные вещи: пустой каталог бывает (волна 5 ещё не приехала).
    var isUnchanged: Bool { unchanged == true }
}

/// Тело `POST /secrets/reveal`.
///
/// `id` — это КЛЮЧ находки (`Discovery.key`), а не её UUID: сервер знает секрет
/// по своему идентификатору из каталога, а загадку — по `"<type>:<geohash7>"`.
struct SecretRevealRequest: Encodable {
    let id: String
    let kind: String
    /// Поездка, на треке которой находка случилась. Ею сервер подтверждает
    /// находку (`verified`), и только если трек уже лежит на сервере.
    let tripId: UUID?
}

/// Ответ `/secrets/reveal` — то, чего на телефоне не было и быть не могло:
/// история, счётчик нашедших, первооткрыватель, редкость.
struct SecretRevealResponse: Decodable {
    struct First: Decodable {
        /// `nil` у непубличного профиля — сервер не называет имени, но факт
        /// первой находки остаётся.
        let displayName: String?
        let foundAt: Date
    }

    let id: String
    let kind: String
    let title: String?
    let story: String?
    let symbol: String?
    let verified: Bool
    /// Дата находки НА СЕРВЕРЕ. Локальную она не трогает никогда — печать
    /// стоит в дате, когда человек там был, и первая находка побеждает.
    let foundAt: Date?
    let finders: Int?
    let first: First?
    let rarity: String?

    /// Вид находки ответа. Незнакомое слово — `nil`, и такой ответ не
    /// применяется вовсе: без вида не вывести id, а угадывать его нельзя.
    var discoveryKind: DiscoveryKind? { DiscoveryKind(rawValue: kind) }

    /// Кому этот ответ адресован: тот же выведенный `id`, что у находки.
    var discoveryId: UUID? {
        discoveryKind.map { Discovery.id(kind: $0, key: id) }
    }
}

/// Два вызова секретов. Протокол, а не прямой `APIClient`, — чтобы каталог и
/// раскрытие проверялись без сети и без `MockURLProtocol` там, где предмет
/// проверки не провод, а решение (обновлять ли, что дописать, куда положить
/// при ошибке).
///
/// Ни протокол, ни реализация НЕ привязаны к главному актёру: каталог
/// обновляется фоновой задачей на старте, и заводить её через главный актёр
/// значило бы разбирать ответ там, где рисуется первый экран. Главного актёра
/// касается ровно одна строка — `APIClient.shared`, и ровно в момент вызова.
protocol SecretsTransport: Sendable {
    func catalog(version: String?) async throws -> SecretCatalogResponse
    func reveal(_ body: SecretRevealRequest) async throws -> SecretRevealResponse
}

/// Настоящий транспорт поверх общего `APIClient` — конверт `{status, payload}`
/// он уже разворачивает сам.
struct SecretsAPI: SecretsTransport {
    /// Свой клиент — только для тестов с `MockURLProtocol`: `init` с ним
    /// `@MainActor`, потому что `APIClient` живёт там. Обычный путь — `init()`
    /// без аргументов, и он собирается с любого потока.
    private let injected: APIClient?

    init() { injected = nil }

    @MainActor
    init(client: APIClient) { injected = client }

    private func client() async -> APIClient {
        if let injected { return injected }
        return await MainActor.run { APIClient.shared }
    }

    /// Каталог — ПУБЛИЧНЫЙ маршрут: `requiresAuth: false`. Иначе человек без
    /// аккаунта (а это состояние по умолчанию) не получил бы ни одного секрета,
    /// хотя в каталоге нет ни одной его строки.
    func catalog(version: String?) async throws -> SecretCatalogResponse {
        try await client().get(
            APIEndpoint.secretsCatalog(version: version), requiresAuth: false)
    }

    func reveal(_ body: SecretRevealRequest) async throws -> SecretRevealResponse {
        try await client().post(APIEndpoint.secretsReveal, body: body)
    }
}
