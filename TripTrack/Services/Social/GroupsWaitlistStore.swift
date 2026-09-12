import Foundation
import OSLog

private let waitlistLog = Logger(subsystem: "com.triptrack", category: "groups.waitlist")

// MARK: - Wire types

struct GroupsWaitlistRequest: Codable {
    let deviceId: UUID
    /// nil = the feature as a whole; a catalog key = one club.
    var clubKey: String? = nil
}

struct GroupsWaitlistState: Codable {
    /// Devices waiting for Clubs to open at all.
    let total: Int
    /// Interest per catalog key.
    let clubs: [String: Int]
    /// Is THIS device on the feature-wide list?
    let joined: Bool
    /// Which clubs this device said it would join.
    let joinedClubs: [String]

    static let empty = GroupsWaitlistState(total: 0, clubs: [:], joined: false, joinedClubs: [])
}

// MARK: - Store

/// The waiting list behind the Groups tab.
///
/// The counter under «Уведомить меня» used to be a string in the layout
/// («Уже ждут 1 240 человек»), and the button only set a local flag — so the
/// number was decoration and the promise was empty: nothing on the server knew
/// anybody wanted this. Both halves are real now, and the join asks for
/// notification permission at the same moment, because a waitlist you cannot
/// be notified from is the same empty promise with a database bill.
@MainActor
final class GroupsWaitlistStore: ObservableObject {
    static let shared = GroupsWaitlistStore()

    @Published private(set) var state: GroupsWaitlistState
    /// Своя ЗАПИСЬ в полёте — и только она. Флаг поднимал и `refresh()`, а на
    /// нём стоит `.disabled` у «Уведомить меня»: экран клубов открывался с
    /// погашенной главной кнопкой на всё время фонового опроса, хотя нажать её
    /// было можно. Читатель гасить кнопку права не имеет.
    @Published private(set) var isJoining = false
    /// Last error, for the one line the tab shows under the CTA.
    @Published private(set) var failed = false

    /// Mirrors the last known counts so the tab opens with a number instead of
    /// a blank while the request is in flight (and offline shows the last
    /// truth rather than zero).
    private static let cacheKey = "groups.waitlist.cache"

    /// Не чаще раза в пять минут: число приходит из кэша мгновенно, а строка
    /// в профиле (0.6.8) зовёт обновление при каждом открытии «Я» — без
    /// ограничения каждый заход в профиль был бы сетевым запросом.
    static let refreshInterval: TimeInterval = 300
    private var lastRefresh: Date?
    /// Счётчик запущенных запросов — см. `run`.
    private var latestRequest = 0

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(GroupsWaitlistState.self, from: data) {
            state = cached
        } else {
            state = .empty
        }
    }

    private var deviceId: UUID { SettingsManager.shared.localUserId }

    func refresh(force: Bool = false) async {
        if !force, let last = lastRefresh, Date().timeIntervalSince(last) < Self.refreshInterval { return }
        await run {
            try await APIClient.shared.post(
                APIEndpoint.groupsWaitlist,
                body: GroupsWaitlistStatusRequest(deviceId: self.deviceId),
                requiresAuth: false
            )
        }
    }

    /// Joins (or leaves, when already on it) the feature-wide list or one club.
    func toggle(clubKey: String? = nil) async {
        let isJoined = clubKey.map { state.joinedClubs.contains($0) } ?? state.joined
        let endpoint = isJoined ? APIEndpoint.groupsWaitlistLeave : APIEndpoint.groupsWaitlistJoin

        // Поднимается ДО запроса разрешения: пока висит системный запрос,
        // второе нажатие завело бы вторую запись.
        isJoining = true
        defer { isJoining = false }

        // Ask for notification permission on the way IN, never on the way out:
        // the whole point of joining is being told when it opens.
        if !isJoined {
            await requestNotificationPermissionIfNeeded()
        }

        await run {
            try await APIClient.shared.post(
                endpoint,
                body: GroupsWaitlistRequest(deviceId: self.deviceId, clubKey: clubKey),
                requiresAuth: false
            )
        }
    }

    func isWaiting(forClub key: String) -> Bool { state.joinedClubs.contains(key) }

    /// People waiting for a club, or nil when nobody is yet — the catalog says
    /// «Будьте первым» rather than printing a zero.
    func waiting(forClub key: String) -> Int? {
        let count = state.clubs[key] ?? 0
        return count > 0 ? count : nil
    }

    // MARK: - Plumbing

    private func run(_ request: @escaping () async throws -> GroupsWaitlistState) async {
        // Номер последнего ЗАПУЩЕННОГО запроса: ответ, пришедший не последним,
        // состояние не трогает. Раньше очередь держал `.disabled` на кнопке —
        // и вместе с ней гасил её на время фонового чтения; без него чтение,
        // начатое до записи и ответившее после неё, вернуло бы «вы не
        // записаны» поверх свежей записи.
        latestRequest += 1
        let ticket = latestRequest
        do {
            let fresh = try await request()
            guard ticket == latestRequest else { return }
            state = fresh
            lastRefresh = Date()
            failed = false
            if let data = try? JSONEncoder().encode(fresh) {
                UserDefaults.standard.set(data, forKey: Self.cacheKey)
            }
        } catch {
            guard ticket == latestRequest else { return }
            failed = true
            waitlistLog.error("waitlist call failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func requestNotificationPermissionIfNeeded() async {
        let manager = NotificationManager.shared
        guard !manager.isAuthorized else { return }
        await withCheckedContinuation { continuation in
            manager.requestAuthorization { _ in continuation.resume() }
        }
        // A fresh grant has to reach the server, or the push we promised has
        // nowhere to land. Signed-out devices have no token to sync — their
        // row still counts, and picks up an account the moment they sign in.
        if manager.isAuthorized, AuthService.shared.isSignedIn {
            PushNotificationManager.shared.registerForRemoteNotifications()
            await PushNotificationManager.shared.syncTokenToServer()
        }
    }
}

struct GroupsWaitlistStatusRequest: Codable {
    let deviceId: UUID
}
