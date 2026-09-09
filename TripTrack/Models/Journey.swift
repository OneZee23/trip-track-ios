import Foundation

/// Путешествие — окно дат над своими поездками.
///
/// Краснодар → Владикавказ (ночёвка) → Тбилиси и обратно — четыре записи и одна
/// история. Плечи путешествия НЕ хранятся списком: это все свои поездки,
/// стартовавшие внутри окна, минус те, что человек убрал (`excludedTripIds`).
/// Поездка, доехавшая с другого телефона позже, попадёт внутрь сама; слияние и
/// разделение путешествий — правка дат, а не операция над треками.
struct Journey: Identifiable, Codable, Equatable {
    let id: UUID
    var userId: UUID?
    /// nil → имя по умолчанию при показе (`JourneyAggregate.defaultTitle`).
    var title: String?
    var startDate: Date
    /// nil → окно открыто: закрывается «Завершить» или правкой дат.
    var endDate: Date?
    var excludedTripIds: [UUID] = []
    /// Только снимок из плеч; nil → карта.
    var coverPhotoId: UUID?
    var isPrivate: Bool = true
    var conflictVersion: Int = 1
    var lastModifiedAt: Date = Date()
    var serverCreatedAt: Date?

    init(id: UUID = UUID(), userId: UUID? = nil, title: String? = nil,
         startDate: Date, endDate: Date?, excludedTripIds: [UUID] = [],
         coverPhotoId: UUID? = nil, isPrivate: Bool = true,
         conflictVersion: Int = 1, lastModifiedAt: Date = Date(), serverCreatedAt: Date? = nil) {
        self.id = id; self.userId = userId; self.title = title
        self.startDate = startDate; self.endDate = endDate
        self.excludedTripIds = excludedTripIds; self.coverPhotoId = coverPhotoId
        self.isPrivate = isPrivate; self.conflictVersion = conflictVersion
        self.lastModifiedAt = lastModifiedAt; self.serverCreatedAt = serverCreatedAt
    }

    /// Поездка внутри окна: старт между границами включительно; открытое окно
    /// принимает всё после старта.
    func contains(_ trip: Trip) -> Bool {
        guard !excludedTripIds.contains(trip.id) else { return false }
        guard trip.startDate >= startDate else { return false }
        if let endDate { return trip.startDate <= endDate }
        return true
    }
}
