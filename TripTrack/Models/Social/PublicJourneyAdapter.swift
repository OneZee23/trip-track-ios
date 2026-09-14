import Foundation

/// Лёгкое плечо из чужого профиля → `Trip` для `JourneyAggregate`/`JourneyCardView`.
/// Тот же приём, что `Trip(social:)`: трек пустой, координаты — из превью;
/// `JourneyAggregate.build` читает только даты, дистанцию, длительность,
/// регион и `previewCoordinates`.
extension Trip {
    init(publicLeg leg: PublicJourneyLeg) {
        let seconds = Double(leg.duration ?? 0)
        self.init(
            id: leg.id,
            startDate: leg.startDate,
            endDate: leg.endDate ?? leg.startDate.addingTimeInterval(seconds),
            distance: leg.distance,
            maxSpeed: 0,
            averageSpeed: seconds > 0 ? leg.distance / seconds : 0,
            trackPoints: [],
            photos: [],
            title: nil,
            tripDescription: nil,
            elevation: 0,
            region: leg.region,
            isPrivate: false,
            vehicleId: nil,
            previewPolyline: leg.previewPolyline.flatMap { Data(base64Encoded: $0) },
            earnedBadgeIds: [],
            isOnServer: true
        )
    }
}

extension Journey {
    /// Путешествие чужого профиля — значения на вход, в базу не пишется.
    init(publicJourney dto: PublicJourneyDto, ownerId: UUID) {
        self.init(id: dto.id, userId: ownerId, title: dto.title, startDate: dto.startDate,
                  endDate: dto.endDate, excludedTripIds: [], coverPhotoId: dto.coverPhotoId,
                  isPrivate: false)
    }
    /// Шапка чужого путешествия с экрана `POST /social/journey`.
    init(socialHead h: SocialJourneyHead) {
        self.init(id: h.id, userId: h.author.id, title: h.title, startDate: h.startDate,
                  endDate: h.endDate, excludedTripIds: [], coverPhotoId: h.coverPhotoId,
                  isPrivate: h.isPrivate)
    }
}

/// Дни окна путешествия для строки в ленте (S7): календарные, включительно;
/// открытое окно считается до `now`. У клиента нет плеч чужого путешествия,
/// чтобы взять `JourneyAggregate.calendarDays`, — окно есть всегда.
enum JourneyWindow {
    static func days(startDate: Date, endDate: Date?, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let end = endDate ?? now
        let a = calendar.startOfDay(for: startDate)
        let b = calendar.startOfDay(for: max(end, startDate))
        return (calendar.dateComponents([.day], from: a, to: b).day ?? 0) + 1
    }
}
