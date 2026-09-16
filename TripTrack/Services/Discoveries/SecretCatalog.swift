import Foundation
import CryptoKit

/// Авторский секрет в бандле — и в нём НЕТ ни координаты, ни названия.
///
/// Лежат только 32-битные усечения `SHA-256(соль ‖ geohash7)`: из них нельзя
/// восстановить, где секрет находится, но можно проверить, что трек прошёл
/// через нужную ячейку. Иначе список секретов читался бы прямо из бандла —
/// и вся ветка «найди сам» превратилась бы в список координат.
///
/// `polygon` — секрет размером с район (например, целый посёлок): у него
/// совпадение ячейки и есть ответ, радиус проверять нечего. Точечному,
/// наоборот, мало попасть в ячейку 150 м — нужно проехать в `reach` от неё.
struct SecretRecord: Codable, Equatable {
    let id: String
    let hashes: [UInt32]
    let reach: Double
    let symbol: SealSymbol
    let polygon: Bool
}

protocol SecretCatalog {
    /// Соль версии набора. Меняется вместе со всеми хешами и никогда — одна.
    var salt: String { get }
    func all() -> [SecretRecord]
}

/// `Secrets.json` из бандла. В 0.7.0 волне 2 список пуст: хеши приедут
/// волной 5, а матчер и каталог должны быть готовы раньше — иначе первый же
/// секрет приехал бы вместе с непроверенным кодом.
final class BundleSecretCatalog: SecretCatalog {
    static let shared = BundleSecretCatalog()

    private(set) var salt: String
    private let secrets: [SecretRecord]

    init(url: URL? = BundleSecretCatalog.bundledURL()) {
        guard let url, let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            print("[SecretCatalog] Secrets.json missing or unreadable")
            salt = Payload.fallbackSalt
            secrets = []
            return
        }
        salt = payload.salt
        secrets = payload.secrets
    }

    func all() -> [SecretRecord] { secrets }

    static func bundledURL() -> URL? {
        var candidates = [Bundle(for: BundleSecretCatalog.self), Bundle.main]
        candidates.append(contentsOf: Bundle.allBundles)
        candidates.append(contentsOf: Bundle.allFrameworks)
        for bundle in candidates {
            if let url = bundle.url(forResource: "Secrets", withExtension: "json") {
                return url
            }
        }
        return nil
    }

    private struct Payload: Decodable {
        static let fallbackSalt = "tt-secrets-v1"
        let salt: String
        let secrets: [SecretRecord]
    }
}

/// Одно место, где считается хеш ячейки.
///
/// Первые ЧЕТЫРЕ байта SHA-256, big-endian. Четырёх байт хватает: набор
/// секретов — десятки записей, и вероятность случайного совпадения ячейки
/// трека с чужим хешем остаётся ничтожной, зато бандл не раздувается в
/// восемь раз ради коллизий, которых не будет.
enum SecretHash {
    static func truncated(salt: String, geohash7: String) -> UInt32 {
        let digest = SHA256.hash(data: Data((salt + geohash7).utf8))
        var value: UInt32 = 0
        for byte in digest.prefix(4) { value = (value << 8) | UInt32(byte) }
        return value
    }
}
