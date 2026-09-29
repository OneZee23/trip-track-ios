import Foundation
import Combine

final class TripsViewModel: ObservableObject {
    @Published var trips: [Trip] = []

    private let tripManager: TripManager

    init(tripManager: TripManager) {
        self.tripManager = tripManager
    }

    func loadTrips() {
        trips = tripManager.fetchTrips()
    }

    func deleteTrip(_ trip: Trip) {
        tripManager.deleteTrip(id: trip.id)
        loadTrips()
    }

    func tripDetail(id: UUID) -> Trip? {
        tripManager.tripDetail(id: id)
    }

    /// Поездки ТОЙ ЖЕ машины за ТОТ ЖЕ календарный день — для раскладки
    /// энергии плагин-гибрида (0.8.3).
    ///
    /// Живёт во вью-модели, а не в экране: это запрос в базу, и правило «что
    /// считается тем же днём» обязано быть в одном месте. День берётся по
    /// СТАРТУ — поездка через полночь целиком относится ко дню, в который её
    /// начали (спека §3.2).
    ///
    /// Сама поездка в ответе есть всегда, даже если строки ещё нет в базе:
    /// экран открывают и с карточки итогов, до того как она туда доедет.
    func tripsOfSameDay(as trip: Trip, vehicleId: UUID,
                        calendar: Calendar = .current) -> [Trip] {
        let dayStart = calendar.startOfDay(for: trip.startDate)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? trip.startDate
        var found = tripManager.fetchTrips(from: dayStart, to: dayEnd).filter {
            $0.vehicleId == vehicleId
                && calendar.isDate($0.startDate, inSameDayAs: trip.startDate)
        }
        if !found.contains(where: { $0.id == trip.id }) { found.append(trip) }
        return found
    }
}
