import Foundation

/// A device-local undo record for a free choice made while PRO is unavailable.
/// Current appearance still uses the existing profile/vehicle sync fields. The
/// extra record is never uploaded and never grants a premium entitlement.
@MainActor
final class CosmeticRetentionStore {
    static let shared = CosmeticRetentionStore()
    static let storageKey = "com.triptrack.cosmetics.retained.v1"

    struct Key: Hashable {
        let rawValue: String
        let kind: ProShowcaseKind

        init(_ kind: ProShowcaseKind, vehicleID: UUID? = nil) {
            self.kind = kind
            rawValue = kind == .vehicleCard
                ? "vehicleCard:\(vehicleID?.uuidString ?? "draft")" : kind.rawValue
        }
    }

    private struct Entry: Codable {
        var premium: String
        var temporary: String
    }

    private struct Ledger: Codable {
        var initialOwner: String?
        // Existing preferences are device-wide. Track their owner so signing
        // into B cannot turn A's pending restore into B's premium selection.
        var owners: [String: String] = [:]
        var pending: [String: [String: Entry]] = [:]
    }

    private let defaults: UserDefaults
    private var ledger: Ledger

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ledger = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(Ledger.self, from: $0) } ?? Ledger()
    }

    /// Lazy adoption preserves existing installations without a data migration.
    /// Only the first known identity may adopt an untagged existing value.
    func activate(owner: String) {
        guard ledger.initialOwner == nil else { return }
        ledger.initialOwner = owner
        persist()
    }

    func selected(_ next: String, replacing current: String,
                  key: Key, owner: String, isPlus: Bool) {
        activate(owner: owner)
        let ownsCurrent = owns(key, owner: owner)
        let isPremium = Self.isPremium(next, for: key.kind)
        if isPlus || isPremium {
            // An intentional free choice while PRO is active is permanent.
            ledger.pending[owner]?[key.rawValue] = nil
        } else if let previous = ledger.pending[owner]?[key.rawValue], ownsCurrent,
                  previous.temporary == current {
            // Carry the reserve forward only while editing this device's
            // temporary choice. A synced replacement starts a new choice.
            ledger.pending[owner]?[key.rawValue] = Entry(
                premium: previous.premium, temporary: next)
        } else if ownsCurrent, Self.isPremium(current, for: key.kind) {
            ledger.pending[owner, default: [:]][key.rawValue] = Entry(
                premium: current, temporary: next)
        } else {
            // A newer free or another owner's choice must not revive an old
            // premium reserve when the user next picks a free appearance.
            ledger.pending[owner]?[key.rawValue] = nil
        }
        ledger.owners[key.rawValue] = owner
        persist()
    }

    /// Used by the banner: name a real retained choice, never a generic promise.
    func retainedID(key: Key, owner: String, current: String) -> String? {
        guard owns(key, owner: owner) else { return nil }
        if Self.isPremium(current, for: key.kind) { return current }
        guard let entry = ledger.pending[owner]?[key.rawValue],
              entry.temporary == current,
              Self.isPremium(entry.premium, for: key.kind) else { return nil }
        return entry.premium
    }

    /// Restore only the exact temporary value written on this device. A newer
    /// remote or other-account choice must not be silently overwritten.
    func restorations(owner: String, current: [Key: String]) -> [Key: String] {
        var result: [Key: String] = [:]
        for (key, value) in current {
            guard owns(key, owner: owner),
                  let entry = ledger.pending[owner]?[key.rawValue],
                  entry.temporary == value,
                  Self.isPremium(entry.premium, for: key.kind) else { continue }
            result[key] = entry.premium
        }
        return result
    }

    func didRestore(key: Key, owner: String, premium: String) {
        guard ledger.pending[owner]?[key.rawValue]?.premium == premium else { return }
        ledger.pending[owner]?[key.rawValue] = nil
        persist()
    }

    func wipe() {
        ledger = Ledger()
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func owns(_ key: Key, owner: String) -> Bool {
        (ledger.owners[key.rawValue] ?? ledger.initialOwner ?? owner) == owner
    }

    private static func isPremium(_ id: String, for kind: ProShowcaseKind) -> Bool {
        ProShowcase.tiles(for: kind).contains { $0.id == id && $0.isPremium }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
