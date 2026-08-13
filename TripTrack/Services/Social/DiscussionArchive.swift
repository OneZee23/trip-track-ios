import Foundation
import OSLog

private let archiveLog = Logger(subsystem: "com.triptrack", category: "discussion-archive")

/// The discussion of a trip, kept on the device.
///
/// Comments live on the server, and taking a trip private with Cloud Sync off
/// removes the trip from the server entirely — which takes the conversation
/// with it. That is the right thing to do for everyone else and the wrong
/// thing to do to the person who was in it: they lose a thread they wrote,
/// with no warning and no way back.
///
/// So the thread is copied here first. On the device, in the app's own
/// container, excluded from backup like the photos are — the same promise the
/// rest of this data lives under. Reading it is the fallback for exactly one
/// situation: the server no longer has the trip, so it cannot answer.
enum DiscussionArchive {
    private static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TripDiscussions", isDirectory: true)
    }

    private static func file(for tripId: UUID) -> URL {
        directory.appendingPathComponent("\(tripId.uuidString).json")
    }

    static func save(_ comments: [TripComment], for tripId: UUID) {
        guard !comments.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            excludeFromBackup(directory)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(comments).write(to: file(for: tripId))
            archiveLog.notice("archived \(comments.count) comments for \(tripId, privacy: .public)")
        } catch {
            archiveLog.error("archive failed: \(error.localizedDescription)")
        }
    }

    /// The reaction list, kept for the same reason and under the same promise.
    static func saveReactions(_ reactions: [SocialReactionEntry], for tripId: UUID) {
        guard !reactions.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            excludeFromBackup(directory)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(reactions).write(to: reactionsFile(for: tripId))
        } catch {
            archiveLog.error("reaction archive failed: \(error.localizedDescription)")
        }
    }

    static func loadReactions(for tripId: UUID) -> [SocialReactionEntry] {
        guard let data = try? Data(contentsOf: reactionsFile(for: tripId)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SocialReactionEntry].self, from: data)) ?? []
    }

    private static func reactionsFile(for tripId: UUID) -> URL {
        directory.appendingPathComponent("\(tripId.uuidString)-reactions.json")
    }

    static func load(for tripId: UUID) -> [TripComment] {
        guard let data = try? Data(contentsOf: file(for: tripId)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([TripComment].self, from: data)) ?? []
    }

    /// Dropped when the trip itself is deleted — an archive of a conversation
    /// about a trip that no longer exists is just an orphan.
    static func discard(for tripId: UUID) {
        try? FileManager.default.removeItem(at: file(for: tripId))
        try? FileManager.default.removeItem(at: reactionsFile(for: tripId))
    }

    private static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
