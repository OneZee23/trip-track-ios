import Foundation

struct VehicleMod: Codable, Identifiable, Hashable {
    static let limit = 100
    static let photoLimit = 6

    var id: UUID = UUID()
    var title: String
    /// Calendar day, independent of the timezone of the phone reading it.
    var date: String
    var odometerKm: Double?
    var photoIds: [UUID] = []

    static func ordered(_ mods: [VehicleMod]) -> [VehicleMod] {
        mods.sorted { $0.date != $1.date ? $0.date > $1.date : $0.id.uuidString < $1.id.uuidString }
    }

    static func decodeJSON(_ json: String?) -> [VehicleMod] {
        guard let data = json?.data(using: .utf8),
            let mods = try? JSONDecoder().decode([VehicleMod].self, from: data)
        else { return [] }
        return mods
    }

    static func encodeJSON(_ mods: [VehicleMod]) -> String? {
        guard let data = try? JSONEncoder().encode(mods) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    var calendarDate: Date? {
        let numbers = date.split(separator: "-").compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: numbers[0], month: numbers[1], day: numbers[2]))
    }

    static func dateBounds(selected: Date, now: Date) -> ClosedRange<Date> {
        let earliest = Date(timeIntervalSince1970: 0)
        return min(earliest, selected, now)...max(earliest, now)
    }
}
