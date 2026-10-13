import Foundation

@MainActor
extension SettingsManager {
    private var cosmeticOwner: String? {
        Self.cosmeticOwner(accountRead: TokenStore.shared.accountIdRead, localID: localUserId)
    }

    static func cosmeticOwner(accountRead: KeychainRead, localID: UUID) -> String? {
        switch accountRead {
        case .value(let data):
            guard let raw = String(data: data, encoding: .utf8),
                  let id = UUID(uuidString: raw) else { return nil }
            return "account:\(id.uuidString)"
        case .missing: return "local:\(localID.uuidString)"
        case .unavailable: return nil
        }
    }

    /// Called by actual selection/vehicle-save actions, never by a sync read.
    func selectCosmetic(_ kind: ProShowcaseKind, id: String,
                        vehicleID: UUID? = nil, isPlus: Bool) {
        guard kind != .vehicleCard || vehicleID != nil else { return }
        let key = CosmeticRetentionStore.Key(kind, vehicleID: vehicleID)
        let current = cosmeticID(kind, vehicleID: vehicleID)
        if let owner = cosmeticOwner {
            CosmeticRetentionStore.shared.selected(
                id, replacing: current, key: key, owner: owner, isPlus: isPlus)
        }
        applyCosmetic(kind, id: id, vehicleID: vehicleID)
    }

    func retainedCosmeticID(_ kind: ProShowcaseKind, current: String,
                            vehicleID: UUID? = nil) -> String? {
        guard kind != .vehicleCard || vehicleID != nil,
              let owner = cosmeticOwner else { return nil }
        return CosmeticRetentionStore.shared.retainedID(
            key: .init(kind, vehicleID: vehicleID), owner: owner, current: current)
    }

    /// Called after StoreKit has resolved the current entitlement, including
    /// cold launch and purchases. Restoration uses the usual sync writers.
    func restoreRetainedCosmetics(isPlus: Bool) {
        let store = CosmeticRetentionStore.shared
        guard let owner = cosmeticOwner else { return }
        store.activate(owner: owner)
        guard isPlus else { return }
        var current: [CosmeticRetentionStore.Key: String] = [
            .init(.profileBackground): profileBackground,
            .init(.avatarFrame): avatarFrame ?? "",
            .init(.routeLine): RouteLineStyle.stored.rawValue
        ]
        for vehicle in vehicles {
            current[.init(.vehicleCard, vehicleID: vehicle.id)] = vehicle.cardStyle ?? ""
        }
        for (key, id) in store.restorations(owner: owner, current: current) {
            let vehicleID = key.kind == .vehicleCard
                ? UUID(uuidString: String(key.rawValue.dropFirst("vehicleCard:".count))) : nil
            applyCosmetic(key.kind, id: id, vehicleID: vehicleID)
            store.didRestore(key: key, owner: owner, premium: id)
        }
    }

    private func cosmeticID(_ kind: ProShowcaseKind, vehicleID: UUID?) -> String {
        switch kind {
        case .profileBackground: return profileBackground
        case .avatarFrame: return avatarFrame ?? ""
        case .routeLine: return RouteLineStyle.stored.rawValue
        case .vehicleCard: return vehicles.first { $0.id == vehicleID }?.cardStyle ?? ""
        }
    }

    private func applyCosmetic(_ kind: ProShowcaseKind, id: String, vehicleID: UUID?) {
        switch kind {
        case .profileBackground: setProfileBackground(id)
        case .avatarFrame: setAvatarFrame(id.isEmpty ? nil : id)
        case .routeLine: RouteLineStyle.stored = RouteLineStyle.from(id)
        case .vehicleCard:
            if let vehicleID { setCardStyle(vehicleId: vehicleID, VehicleCardStyle.from(id)) }
        }
    }
}
