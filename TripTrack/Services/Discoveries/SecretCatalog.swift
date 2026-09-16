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

extension SecretRecord {
    /// Незнакомая печать — `.generic`, а не отказ разбора.
    ///
    /// `symbol` в `Secrets.json` и на сервере — СТРОКА, и печать заводится
    /// первой там, где её рисуют. Значит бывает и обратный порядок: сборка
    /// с новой гравюрой в бандле, но со старым `SealSymbol` в коде — или
    /// секрет, приехавший каталогом с сервера, который уже знает печать из
    /// следующей версии. Строгий разбор уронил бы ВЕСЬ файл на одной
    /// незнакомой строке: `JSONDecoder` бросает на первой ошибке, и человек
    /// остался бы без всех секретов сразу, включая давно найденные. Простая
    /// печать вместо гравюры — та же потеря, что у сервера
    /// (`riddle-symbol.util.ts`), и стоит она одну картинку, а не весь набор.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        hashes = try container.decode([UInt32].self, forKey: .hashes)
        reach = try container.decodeIfPresent(Double.self, forKey: .reach) ?? 0
        polygon = try container.decodeIfPresent(Bool.self, forKey: .polygon) ?? false
        let raw = try container.decode(String.self, forKey: .symbol)
        symbol = SealSymbol(rawValue: raw) ?? .generic
    }
}

protocol SecretCatalog {
    /// Соль версии набора. Меняется вместе со всеми хешами и никогда — одна.
    var salt: String { get }
    func all() -> [SecretRecord]
}

/// `Secrets.json` из бандла. В 0.7.0 он ПУСТ, и это решение, а не задел:
/// авторский секрет приходит каталогом с сервера (`CachedSecretCatalog`,
/// обновление раз в сутки) и находится только после того, как владелец
/// активировал строку вместе с её историей. Положить хеши в бандл значило бы
/// отдать проехавшему через район безымянную печать и именной эпический
/// значок раньше, чем у секрета появился текст. Настоящие числа при этом
/// проверяются тестами — фикстурой `TripTrackTests/Fixtures/`.
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
