import AppIntents
import Foundation

/// Surfaces a `Vehicle` in the Shortcuts app so users can pick which car a
/// "Start Trip" shortcut should use. The query reads from `SettingsManager`
/// so the picker mirrors whatever vehicles the user has in the garage.
struct VehicleAppEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Vehicle"
    static var defaultQuery = VehicleEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct VehicleEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [VehicleAppEntity] {
        SettingsManager.shared.vehicles
            .filter { identifiers.contains($0.id) }
            .map { VehicleAppEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [VehicleAppEntity] {
        SettingsManager.shared.vehicles
            .map { VehicleAppEntity(id: $0.id, name: $0.name) }
    }
}
