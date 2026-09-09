import Foundation
import CoreLocation

struct TripPhoto: Identifiable, Codable, Equatable {
    let id: UUID
    let filename: String
    let caption: String?
    /// Когда снимок попал в поездку. НЕ время съёмки — оно ниже.
    let timestamp: Date

    /// Когда кадр действительно снят, из библиотеки фотографий.
    ///
    /// Отдельно от `timestamp` не для порядка: тот ставится в момент
    /// сохранения и может отличаться на дни — снимок легко добавить к поездке
    /// назавтра. Ставить кадр на маршрут по времени сохранения значило бы
    /// увезти его за сотню километров от места съёмки.
    ///
    /// `nil` у всех снимков, добавленных до 0.6.5: тогда это просто не
    /// сохраняли, и восстановить неоткуда.
    var capturedAt: Date?

    /// Координата из самого снимка, когда она в нём есть.
    ///
    /// Правда о том, где стояла камера, — точнее любого вычисления по треку.
    /// Но её часто нет вовсе: геометки выключены у многих, а кадр, пришедший
    /// через мессенджер, теряет их всегда.
    var exifLatitude: Double?
    var exifLongitude: Double?

    var exifCoordinate: CLLocationCoordinate2D? {
        guard let lat = exifLatitude, let lon = exifLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    init(
        id: UUID,
        filename: String,
        caption: String?,
        timestamp: Date,
        capturedAt: Date? = nil,
        exifLatitude: Double? = nil,
        exifLongitude: Double? = nil
    ) {
        self.id = id
        self.filename = filename
        self.caption = caption
        self.timestamp = timestamp
        self.capturedAt = capturedAt
        self.exifLatitude = exifLatitude
        self.exifLongitude = exifLongitude
    }
}
