import Foundation

enum AutoRecordMode: String, CaseIterable, Codable {
    case off
    case remind
    case auto
}

struct SavedBluetoothDevice: Codable, Identifiable, Equatable {
    let uuid: String
    let name: String
    var vehicleId: UUID?

    var id: String { uuid }
}
