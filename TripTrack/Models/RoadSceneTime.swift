import Foundation

enum RoadSceneTime: String, CaseIterable {
    case dawn, day, sunset, night

    var assetName: String { "RoadScene/" + rawValue }

    /// Местные часы: рассвет 05:00..<08:00, день 08:00..<17:00,
    /// закат 17:00..<20:00, ночь 20:00..<05:00. Геопозиция не нужна.
    static func slot(for date: Date, calendar: Calendar = .current) -> RoadSceneTime {
        switch calendar.component(.hour, from: date) {
        case 5..<8: return .dawn
        case 8..<17: return .day
        case 17..<20: return .sunset
        default: return .night
        }
    }

    static func current() -> RoadSceneTime {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-debug-road-time"),
           arguments.indices.contains(index + 1),
           let forced = RoadSceneTime(rawValue: arguments[index + 1]) {
            return forced
        }
        #endif
        return slot(for: Date())
    }
}
