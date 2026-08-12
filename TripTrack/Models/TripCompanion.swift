import Foundation

/// Someone who was in the car with you.
///
/// Local for now, and honest about it: a companion is a name and a face you
/// attach to a trip, stored with the trip on this device. Linking them to a
/// real account — so the trip shows up in THEIR history, so they can add their
/// own photos, so they get asked first — needs the server to know what a
/// companion is, and it does not yet. `accountId` is where that link will go;
/// everything else about the feature works without it.
struct TripCompanion: Identifiable, Codable, Hashable {
    let id: UUID
    /// What you call them — «Аня», «Дмитрий П.», «Папа».
    var name: String
    /// Emoji face, chosen from a small palette. Not a photo: a photo of another
    /// person is theirs to give, not ours to store because they sat in a car.
    var avatar: String
    /// Set once companions are real accounts. Nil means a local label.
    var accountId: String?

    init(id: UUID = UUID(), name: String, avatar: String = "🙂", accountId: String? = nil) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.accountId = accountId
    }

    /// Longest name the row will show without turning into a paragraph.
    static let nameLimit = 24

    /// Faces offered when adding someone. Deliberately a short list — this is
    /// a marker so you can tell two companions apart at a glance, not an
    /// avatar builder.
    static let avatarPalette = [
        "🙂", "😎", "🐻", "🐱", "🦊", "🐼", "🦁", "🐧",
        "👩", "👨", "🧑", "👵", "👴", "🚀", "⚡️", "🌿"
    ]
}

extension Array where Element == TripCompanion {
    /// «Аня К., Дмитрий П.» — the line under the faces.
    var displayNames: String {
        map(\.name).joined(separator: ", ")
    }
}
