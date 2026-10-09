import Foundation
import Combine

/// First-party, opt-in counters. Completely independent of login/cloud sync.
/// The payload has no account/trip/device identifiers: `token` is a fresh random
/// secret for this consent period, also used to erase its server-side counters.
struct ProductAnalyticsSnapshot: Codable, Equatable {
    var schema = 1
    var token = UUID().uuidString.lowercased()
    var revision = 1
    var cohortDay: String
    var observedDay: String
    var hadTrips: Bool
    var starts = 0
    var saves = 0
    var saveFailures = 0
    var atlasOpens = 0
    var fastSaves = 0
    var mediumSaves = 0
    var slowSaves = 0
    var firstSaveDay: String?
    var secondSaveDay: String?
}

/// Mutated on the main queue, like TripManager and the settings UI. State is
/// one bounded snapshot, not a growing event/route log. Retry sends the same
/// revision; the server replaces counters rather than adding them again.
final class ProductAnalytics: ObservableObject {
    static let shared = ProductAnalytics()
    private static let key = "productAnalytics.v1"
    struct State: Codable {
        var snapshot: ProductAnalyticsSnapshot?
        var activeRecording: UUID? // stays on-device; survives interrupted recordings
        var pendingErase: [String] = []
        var acknowledgedRevision = 0
    }
    @Published private(set) var enabled: Bool
    @Published private(set) var deletionPending: Bool
    private var state: State
    private let defaults: UserDefaults
    private let now: () -> Date
    private let session: URLSession
    private let networkEnabled: Bool
    private var request: URLSessionDataTask?
    private var scheduled: DispatchWorkItem?

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         session: URLSession? = nil, networkEnabled: Bool = !AppConfig.isDebug) {
        self.defaults = defaults
        self.now = now
        self.networkEnabled = networkEnabled
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        self.session = session ?? URLSession(configuration: configuration)
        state = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
        enabled = state.snapshot != nil
        deletionPending = !state.pendingErase.isEmpty
    }

    func setEnabled(_ value: Bool, hadTrips: Bool = false) {
        guard value != enabled else { return }
        if value {
            // Avoid an unbounded erase queue if consent is toggled offline.
            guard state.pendingErase.count < 16 else { return }
            let day = Self.day(now())
            state.snapshot = ProductAnalyticsSnapshot(cohortDay: day, observedDay: day, hadTrips: hadTrips)
            state.acknowledgedRevision = 0
        } else {
            if let token = state.snapshot?.token { state.pendingErase.append(token) }
            state.snapshot = nil
        }
        state.activeRecording = nil
        enabled = value
        persist()
        scheduleFlush()
    }

    func recordingStarted(id: UUID) {
        guard enabled, state.activeRecording != id else { return }
        state.activeRecording = id
        update { $0.starts = min(1_000_000, $0.starts + 1) }
    }

    func recordingFinished(id: UUID, saved: Bool, eligible: Bool, elapsed: TimeInterval) {
        guard enabled, state.activeRecording == id else { return }
        state.activeRecording = nil
        let day = Self.day(now())
        update { snapshot in
            if !saved { snapshot.saveFailures = min(1_000_000, snapshot.saveFailures + 1) }
            guard saved && eligible else { return }
            snapshot.saves = min(1_000_000, snapshot.saves + 1)
            if snapshot.saves == 1 { snapshot.firstSaveDay = day }
            if snapshot.saves == 2 { snapshot.secondSaveDay = day }
            if elapsed < 0.1 { snapshot.fastSaves = min(1_000_000, snapshot.fastSaves + 1) }
            else if elapsed < 1 { snapshot.mediumSaves = min(1_000_000, snapshot.mediumSaves + 1) }
            else { snapshot.slowSaves = min(1_000_000, snapshot.slowSaves + 1) }
        }
    }

    func atlasOpened() {
        update { $0.atlasOpens = min(1_000_000, $0.atlasOpens + 1) }
    }

    private func update(_ change: (inout ProductAnalyticsSnapshot) -> Void) {
        guard var snapshot = state.snapshot else { return }
        change(&snapshot)
        snapshot.revision += 1
        snapshot.observedDay = Self.day(now())
        state.snapshot = snapshot
        persist()
        scheduleFlush()
    }

    private func persist() {
        deletionPending = !state.pendingErase.isEmpty
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Self.key) }
    }

    private func scheduleFlush() {
        scheduled?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        scheduled = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    /// Foreground/network restoration retries a failed upload, even with Cloud
    /// Sync off. No background task, GPS wake-up, login or refresh-token request.
    func flush() {
        guard networkEnabled, request == nil else { return }
        let eraseToken = state.pendingErase.first
        let snapshot = state.snapshot
        let data: Data
        let path: String
        if let eraseToken {
            path = "usage/erase"
            guard let encoded = try? JSONEncoder().encode(["token": eraseToken]) else { return }
            data = encoded
        } else {
            guard var snapshot, snapshot.revision > state.acknowledgedRevision else { return }
            // Retry old offline counts with today's delivery day. Cohort and
            // milestone dates remain the dates of the actual local actions.
            snapshot.observedDay = Self.day(now())
            path = "usage/snapshot"
            guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
            data = encoded
        }
        var req = URLRequest(url: AppConfig.apiBaseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        request = session.dataTask(with: req) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.request = nil
                guard error == nil, let response = response as? HTTPURLResponse,
                      response.statusCode == 204 else { return }
                if let eraseToken {
                    self.state.pendingErase.removeAll { $0 == eraseToken }
                } else if let snapshot, self.state.snapshot?.token == snapshot.token {
                    self.state.acknowledgedRevision = snapshot.revision
                }
                self.persist()
                // Consent may have been revoked during the request. Deletion
                // follows it, and a server tombstone blocks delayed retries.
                self.scheduleFlush()
            }
        }
        request?.resume()
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
