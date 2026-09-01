import Foundation

/// Records whether the SERVER has acknowledged our profile push.
///
/// `account.display_name` has exactly one writer — `POST /auth/profile-update`
/// from `AuthService.syncProfileToServer`. Account creation never sets a name,
/// so until that push lands the account is nameless and every other user sees
/// the client's «Пользователь» placeholder. The push is fire-and-forget, and
/// the server validates the request as a whole: one unlisted `language`, one
/// over-long name, one dropped connection, and the name is gone.
///
/// Before this latch existed the launch-time retry asked whether the KEYCHAIN
/// had a name. That is a question about this phone, and it answered "yes" for
/// exactly the users whose push had been rejected — so the retry never fired
/// and eight prod accounts stayed nameless for weeks (2026-08-31).
///
/// The rule: an absent record means «not confirmed», never «done». Accounts
/// broken before this shipped carry no record, and that is precisely who has
/// to push again. It costs every healthy account one extra request on the
/// first launch after the update, once.
enum ProfileSyncLatch {
    private static let confirmedKey = "com.triptrack.profile.syncConfirmed"

    /// The server accepted a profile push. Call ONLY on a 2xx-with-ok-envelope.
    static func markConfirmed(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: confirmedKey)
    }

    /// The server rejected the push, or it never got there. Reopens the latch
    /// so the next launch tries again.
    static func markUnconfirmed(_ defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: confirmedKey)
    }

    /// Sign-out. The next Apple ID on this phone inherits nothing — a stale
    /// «confirmed» would swallow its very first push.
    static func reset(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: confirmedKey)
    }

    /// Whether the profile still owes the server a push.
    static func needsPush(
        isSignedIn: Bool,
        localName: String?,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard isSignedIn else { return false }
        // No name anywhere: generate one and push it — the original behaviour.
        if localName?.trimmingCharacters(in: .whitespaces).isEmpty ?? true { return true }
        // A name on this phone proves nothing about the server. `bool(forKey:)`
        // is false for an absent key, which is the answer we want: never
        // recorded reads as never confirmed.
        return !defaults.bool(forKey: confirmedKey)
    }
}
