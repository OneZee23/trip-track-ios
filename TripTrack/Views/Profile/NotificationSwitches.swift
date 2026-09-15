import SwiftUI
import OSLog

private let notifSwitchLog = Logger(subsystem: "com.triptrack", category: "settings")

// MARK: - Notification switches

struct NotificationSwitchesResponse: Decodable {
    let notifyReactions: Bool
    let notifyFollows: Bool
    /// Optional: some deployed backends predate the comments and companions
    /// rollouts and don't return these keys. Missing = server default (true).
    let notifyComments: Bool?
    let notifyWeeklyRecap: Bool
    let notifyCompanions: Bool?
    /// 0.7.0. Оба ключа опциональны: сервер, задеплоенный до этой версии, их
    /// не шлёт — и отсутствие `isAdmin` значит «не админ», то есть карточки
    /// нет. Молчание никогда не выдаёт админские права.
    let isAdmin: Bool?
    let notifyNewAccounts: Bool?
}

struct NotificationSwitchesUpdate: Encodable {
    let notifyReactions: Bool
    let notifyFollows: Bool
    let notifyComments: Bool
    let notifyWeeklyRecap: Bool
    let notifyCompanions: Bool
    /// Уезжает всегда, у кого угодно: сервер пишет его ТОЛЬКО админу, а
    /// у остальных молча игнорирует (см. план 0.7.0). Условная отправка
    /// потребовала бы второй формы пейлоада ради ключа, который и так
    /// никому не вредит.
    let notifyNewAccounts: Bool
}

/// The «Уведомления» master canon puts in Настройки, over the same
/// `/auth/notification-prefs` payload the detailed screen edits (Входящие →
/// ⚙). It is the server's, not the device's: iOS permission is separate and
/// stays where iOS put it.
///
/// «Уведомления» is DERIVED — the server has no master flag, only the five
/// categories, so it is off exactly when all five are. Muting stashes the
/// pre-mute set and puts it back on the way up; without that, one tap on the
/// master flattens a hand-picked selection into "everything on" and the user
/// never learns why.
///
/// Four of the five categories are edited one screen over (Входящие → ⚙); the
/// fifth, «Добавление в попутчики», is also offered on «Приватность», which is
/// why this class publishes it. It reads all five either way, so the master can
/// be derived and the untouched ones written back unchanged.
///
/// ONE instance per settings tree: `ProfileSettingsSheet` owns it and hands the
/// same object to `PrivacySettingsView`. Two instances would each load, each
/// write all five flags, and the second save would post a stale copy of
/// whatever the first one changed.
@MainActor
final class NotificationSwitches: ObservableObject {
    @Published private(set) var isLoaded = false
    @Published private(set) var master = true

    /// Флаг `is_admin` из ответа сервера. Единственный источник — БД, где его
    /// ставят руками; ни эндпоинта, ни списка email в клиенте нет. `false`
    /// при любом сомнении: старый сервер, ошибка загрузки, гость.
    @Published private(set) var isAdmin = false

    /// «Новые пользователи» — пуш админу о КАЖДОЙ чужой регистрации.
    /// В `master` НЕ входит нарочно: общий выключатель «Уведомления»
    /// обещает тишину про твои события, а это событие чужое, и схлопнуть
    /// их в один тумблер значило бы соврать в обе стороны.
    @Published private(set) var newAccounts = true

    /// Published because «Приватность» edits it (`PrivacySettingsView`). The
    /// other four are not: they belong to the detailed screen (Входящие → ⚙),
    /// and are held here only because the master is DERIVED from all five and
    /// the update payload has to carry them back unchanged.
    @Published private(set) var companions = true
    private var reactions = true
    private var follows = true
    private var comments = true
    private var weeklyRecap = true
    /// Debounced save — flipping the master and then a category collapses
    /// into one POST carrying the final state.
    private var saveTask: Task<Void, Never>?

    private static let preMuteKey = "com.triptrack.settings.notificationsPreMute"

    /// Вставной клиент — чтобы тесты читали тело POST'а с провода через
    /// `MockURLProtocol`, как `CompanionsStore`. В приложении всегда `.shared`.
    private let client: APIClient

    #if DEBUG
    /// `-debug-admin` рисует карточку «Админ» так, как её увидит владелец:
    /// без сервера с `is_admin = true` её не показать ни на симуляторе, ни на
    /// снимке. Компилируется только в debug и в релиз не попадает.
    static let forcesAdmin = ProcessInfo.processInfo.arguments.contains("-debug-admin")
    #endif

    init(client: APIClient = .shared) {
        self.client = client
        #if DEBUG
        if Self.forcesAdmin {
            isAdmin = true
            // Тумблеры рисуются активными: дальше `load()` выйдет на первом
            // же `guard`, а сервера, который ответил бы, на симуляторе нет.
            isLoaded = true
        }
        #endif
    }

    func load() async {
        guard !isLoaded else { return }
        do {
            let res: NotificationSwitchesResponse = try await client.post(
                APIEndpoint.notificationPrefsGet, body: EmptyRequest())
            reactions = res.notifyReactions
            follows = res.notifyFollows
            comments = res.notifyComments ?? true
            weeklyRecap = res.notifyWeeklyRecap
            companions = res.notifyCompanions ?? true
            isAdmin = Self.resolveAdmin(res.isAdmin)
            newAccounts = res.notifyNewAccounts ?? true
            refreshMaster()
        } catch {
            // Same optimistic default as the detailed screen: a load failure
            // shows an account that isn't muted, because it isn't.
            notifSwitchLog.error("notification prefs load failed: \(error.localizedDescription)")
        }
        isLoaded = true
    }

    func setMaster(_ on: Bool) {
        guard on != master else { return }
        if on {
            let restored = Self.preMuteSet()
            reactions = restored?[0] ?? true
            follows = restored?[1] ?? true
            comments = restored?[2] ?? true
            weeklyRecap = restored?[3] ?? true
            companions = restored?[4] ?? true
        } else {
            UserDefaults.standard.set(
                [reactions, follows, comments, weeklyRecap, companions],
                forKey: Self.preMuteKey
            )
            reactions = false
            follows = false
            comments = false
            weeklyRecap = false
            companions = false
        }
        refreshMaster()
        scheduleSave()
    }

    /// «Добавление в попутчики». Flipping it can move the derived master too —
    /// muting the last live category IS muting the account, and the switch one
    /// screen up has to say so.
    func setCompanions(_ on: Bool) {
        guard on != companions else { return }
        companions = on
        refreshMaster()
        scheduleSave()
    }

    /// «Новые пользователи». Оптимистично — и тем же отложенным POST'ом,
    /// что остальные категории; `master` он не трогает.
    func setNewAccounts(_ on: Bool) {
        guard on != newAccounts else { return }
        newAccounts = on
        scheduleSave()
    }

    /// Отсутствие ключа — это «не админ», а не «неизвестно»: карточку,
    /// которую нечем подтвердить, не показываем.
    static func resolveAdmin(_ remote: Bool?) -> Bool {
        #if DEBUG
        return (remote ?? false) || forcesAdmin
        #else
        return remote ?? false
        #endif
    }

    private func refreshMaster() {
        master = reactions || follows || comments || weeklyRecap || companions
    }

    /// The set as it stood before the last mute — nil when there is none, or
    /// when it was written by an older build with a different shape, or when
    /// it is all-off (which cannot be restored: the master would still read
    /// off, and the switch the user just turned on would snap back).
    private static func preMuteSet() -> [Bool]? {
        guard let stored = UserDefaults.standard.array(forKey: preMuteKey) as? [Bool],
              stored.count == 5,
              stored.contains(true) else { return nil }
        return stored
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await save()
        }
    }

    private func save() async {
        do {
            let _: NotificationSwitchesResponse = try await client.post(
                APIEndpoint.notificationPrefsUpdate,
                body: NotificationSwitchesUpdate(
                    notifyReactions: reactions,
                    notifyFollows: follows,
                    notifyComments: comments,
                    notifyWeeklyRecap: weeklyRecap,
                    notifyCompanions: companions,
                    notifyNewAccounts: newAccounts
                ))
        } catch {
            notifSwitchLog.error("notification prefs save failed: \(error.localizedDescription)")
        }
    }
}
