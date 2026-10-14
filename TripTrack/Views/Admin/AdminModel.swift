import Foundation
import OSLog

private let adminLog = Logger(subsystem: "com.triptrack", category: "admin")

/// Что отдаёт `/admin/*` (0.9.0). Имён и почты в ответе нет: подписку
/// узнают по хвосту транзакции, датам и языку аккаунта.
struct AdminSummary: Decodable, Equatable {
    let accounts: Int
    let accountsNew7d: Int
    let accountsActive7d: Int
    let proActive: Int
    let proTrial: Int
    let proPaid: Int
    let trips: Int
    let tripsManual: Int
}

struct AdminSubscription: Decodable, Identifiable, Equatable {
    let txTail: String
    let product: String
    /// `active`, `grace`, `expired`, `revoked` или `unattached` — Apple
    /// сообщила о покупке, а телефон так и не привязал её к аккаунту.
    let status: String
    let isTrial: Bool
    let autoRenew: Bool
    let expiresAt: Date?
    let createdAt: Date
    let attached: Bool
    let isAdmin: Bool
    let language: String?
    let accountCreatedAt: Date?
    let trips: Int

    var id: String { "\(txTail)-\(createdAt.timeIntervalSince1970)" }
    var isYearly: Bool { product.hasSuffix(".yearly") }
}

struct AdminEvent: Decodable, Identifiable, Equatable {
    let txTail: String?
    let type: String
    let subtype: String?
    let outcome: String?
    let at: Date

    var id: String { "\(type)-\(subtype ?? "")-\(at.timeIntervalSince1970)-\(txTail ?? "")" }
}

struct AdminFlag: Decodable, Identifiable, Equatable {
    let name: String
    /// `nil` — на сервере значения нет, действует вшитое в приложение.
    let enabled: Bool?
    var id: String { name }
}

private struct AdminItems<T: Decodable>: Decodable { let items: [T] }
private struct AdminFlagRequest: Encodable { let name: String; let enabled: Bool }

/// Состояние экрана «Админка». Грузит четыре ответа параллельно: экран
/// открывают, чтобы посмотреть сразу всё.
@MainActor
final class AdminModel: ObservableObject {
    @Published private(set) var summary: AdminSummary?
    @Published private(set) var subscriptions: [AdminSubscription] = []
    @Published private(set) var events: [AdminEvent] = []
    @Published private(set) var flags: [AdminFlag] = []
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    /// Флаг, чей переключатель сейчас уходит на сервер.
    @Published private(set) var savingFlag: String?

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func load() async {
        isLoading = true
        failed = false
        defer { isLoading = false }
        do {
            async let s: AdminSummary = client.post(APIEndpoint.adminSummary, body: EmptyRequest())
            async let subs: AdminItems<AdminSubscription> = client.post(APIEndpoint.adminSubscriptions, body: EmptyRequest())
            async let ev: AdminItems<AdminEvent> = client.post(APIEndpoint.adminEvents, body: EmptyRequest())
            async let fl: AdminItems<AdminFlag> = client.post(APIEndpoint.adminFlags, body: EmptyRequest())
            let (summary, subscriptions, events, flags) = try await (s, subs, ev, fl)
            self.summary = summary
            self.subscriptions = subscriptions.items
            self.events = events.items
            self.flags = flags.items
        } catch {
            // В лог — вид ошибки, а не текст сервера: тот же класс данных, что
            // чистит `PIIScrubber`.
            adminLog.error("admin load failed: \(String(describing: type(of: error)), privacy: .public)")
            failed = true
        }
    }

    /// Пока ответ не пришёл, переключатель показывает новое значение, а
    /// отказ возвращает прежнее — и экран честно говорит, что не вышло.
    func setFlag(_ name: String, enabled: Bool) async {
        let before = flags
        flags = flags.map { $0.name == name ? AdminFlag(name: name, enabled: enabled) : $0 }
        savingFlag = name
        defer { savingFlag = nil }
        do {
            let res: AdminItems<AdminFlag> = try await client.post(
                APIEndpoint.adminFlag, body: AdminFlagRequest(name: name, enabled: enabled))
            flags = res.items
        } catch {
            adminLog.error("admin flag failed: \(String(describing: type(of: error)), privacy: .public)")
            flags = before
            failed = true
        }
    }
}
