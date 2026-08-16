import Foundation

/// The sync cursor, paired with the identity of the store it describes.
///
/// `reset(for:)` shipped for five versions with ZERO callers, so the cursor in
/// UserDefaults outlived the SQLite store it belonged to. When the store was
/// replaced — the old `PersistenceController` did that on any load error, in
/// Release, silently — the client stayed pinned to an incremental pull that
/// asked "what changed since Tuesday", got the honest answer "nothing", and
/// left a real user's 107 trips sitting on the server while his phone showed an
/// empty library. Signing out and back in did not help, because sign-out turns
/// Cloud Sync off and `runFullSync` returns before it ever pulls.
///
/// The stamp has to be born inside the store and die with it. Kept in
/// UserDefaults alone it would survive the wipe right next to the cursor and
/// still match — guarding nothing. Copied into a fresh store on first launch it
/// would "restore" the old identity after the loss, which is worse. So it flows
/// store → UserDefaults only, and it is Core Data's own `NSStoreUUIDKey`, which
/// this app never writes and therefore cannot forge.
///
/// Both loss directions land safely:
///   * store lost, UserDefaults kept → stamp mismatch → cursor dropped → full pull
///   * UserDefaults lost, store kept → no cursor at all → full pull
///
/// A full pull is idempotent upserts, so being too eager costs bandwidth, never
/// data. (It costs one more thing: a full pull always carries the settings row,
/// which is why `applyRemoteSettings` merges progress monotonically instead of
/// assigning it.)
enum LastSyncedAtStore {
    private static let prefix = "com.triptrack.sync.lastSyncedAt"

    private static func dateKey(_ accountId: UUID) -> String { "\(prefix).\(accountId)" }
    private static func stampKey(_ accountId: UUID) -> String { "\(prefix).\(accountId).store" }

    /// - Parameters:
    ///   - storeIdentity: injectable for tests; production reads the live store.
    static func get(
        accountId: UUID,
        storeIdentity: String? = PersistenceController.shared.storeIdentity,
        defaults: UserDefaults = .standard
    ) -> Date? {
        // NB: the stamp is never adopted here. A line that read the current
        // identity and remembered it would silently disarm the whole guard —
        // which is exactly the shape of the bug this replaces.
        guard let storeIdentity,
              defaults.string(forKey: stampKey(accountId)) == storeIdentity
        else { return nil }
        return defaults.object(forKey: dateKey(accountId)) as? Date
    }

    static func set(
        _ date: Date, for accountId: UUID,
        storeIdentity: String? = PersistenceController.shared.storeIdentity,
        defaults: UserDefaults = .standard
    ) {
        // No store open means nothing worth remembering: the rows this cursor
        // would describe were never persisted.
        guard let storeIdentity else { return }
        // Stamp first. A crash between the two writes then leaves a stamp with
        // no date, and `get` answers nil — the safe direction.
        defaults.set(storeIdentity, forKey: stampKey(accountId))
        defaults.set(date, forKey: dateKey(accountId))
    }

    static func reset(for accountId: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: dateKey(accountId))
        defaults.removeObject(forKey: stampKey(accountId))
    }
}
