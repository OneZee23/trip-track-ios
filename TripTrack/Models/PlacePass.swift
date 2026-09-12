import Foundation

/// Проезд — факт «трек этой поездки прошёл в 100 м от места».
///
/// Одна поездка даёт столько проездов, сколько раз прошла мимо: дорога «туда и
/// обратно» — два проезда с противоположным курсом, и «обычно занимает» у них
/// разное. Считает `TripRouteLocator.passes(near:)` — тем же пятиметровым
/// шагом, что и одометр, иначе «до моря 143 км» разошлось бы с итогом поездки.
struct PlacePass: Identifiable, Equatable {
    let id: UUID
    let placeId: UUID
    let tripId: UUID
    /// Момент проезда — время ближайшей точки трека.
    let timestamp: Date
    /// Секунды от старта поездки.
    let elapsedFromStart: TimeInterval
    /// Метры от старта по треку.
    let distanceFromStart: Double
    /// Курс в точке проезда, градусы 0…360; `unknownCourse`, если ни у точки,
    /// ни у соседей его нет. Хранится, а не додумывается: «обычно» считается
    /// по проездам одного направления, иначе медиана смешает дорогу к морю с
    /// дорогой домой.
    let course: Double

    static let unknownCourse: Double = -1

    var hasCourse: Bool { course >= 0 }

    init(id: UUID = UUID(), placeId: UUID, tripId: UUID, timestamp: Date,
         elapsedFromStart: TimeInterval, distanceFromStart: Double, course: Double) {
        self.id = id
        self.placeId = placeId
        self.tripId = tripId
        self.timestamp = timestamp
        self.elapsedFromStart = elapsedFromStart
        self.distanceFromStart = distanceFromStart
        self.course = course
    }
}
