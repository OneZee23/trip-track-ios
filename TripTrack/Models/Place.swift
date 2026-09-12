import Foundation
import CoreLocation
import CryptoKit

/// Место — точка на дороге, которую приложение узнаёт на каждом проезде.
///
/// Джубга по дороге к морю, пост на трассе, поворот на дачу. Человек ставит
/// отметку один раз, и дальше приложение само знает: «вы здесь в 11-й раз,
/// обычно доезжаете за 2:14». Не «сегмент» с воротами и коридором — это
/// модель соревнований по времени, которых у нас не будет никогда; личной
/// истории хватает точки и радиуса.
///
/// **Место рождается из отметки и живёт только на телефоне.** Оно выводится
/// из отметок и треков, которые синхронизируются и так, поэтому своего
/// провода у него нет. Чтобы два телефона сошлись без синка, `id` — функция
/// от ячейки (`id(forCell:)`), а ячейка — geohash-7 (~150 м, «один двор»):
/// две отметки в одной ячейке — одно место.
struct Place: Identifiable, Equatable {
    let id: UUID
    /// geohash-7, из которого выведен `id`.
    let cell: String
    /// Центроид отметок этого места — не центр ячейки: отметку ставят у
    /// поворота, а не посреди квадрата.
    var latitude: Double
    var longitude: Double
    /// Имя первой отметки с именем (геокодер называет отметки сам). Пусто —
    /// законно; экран покажет ячейку.
    var name: String?
    let createdAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Ячейка места. 7 знаков ≈ 153 × 153 м — двор, а не квартал.
    static let cellPrecision = 7

    static func cell(latitude: Double, longitude: Double) -> String {
        GeohashEncoder.encode(latitude: latitude, longitude: longitude, precision: cellPrecision)
    }

    /// Пространство имён мест TripTrack. НАВСЕГДА: от него зависят id на всех
    /// телефонах, и смена превратит каждую отметку в чужую.
    static let namespace = UUID(uuidString: "3C7A9C2E-5D3B-4F4E-8A1B-6E2F0D9C7B5A")!

    /// UUID v5 (RFC 4122 §4.3) от ячейки: SHA-1 над байтами пространства имён
    /// и UTF-8 ячейки, биты версии и варианта — как в RFC. Совпадает с
    /// `uuid.uuid5` в Python, чем и заморожены векторы `PlaceIdentityTests`.
    static func id(forCell cell: String) -> UUID {
        var data = Data()
        withUnsafeBytes(of: namespace.uuid) { data.append(contentsOf: $0) }
        data.append(contentsOf: Array(cell.utf8))
        var b = Array(Insecure.SHA1.hash(data: data))
        b[6] = (b[6] & 0x0F) | 0x50
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}
