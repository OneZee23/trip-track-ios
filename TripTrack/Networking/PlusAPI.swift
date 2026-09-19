import Foundation

/// Тело `POST /plus/attach` — подписанная Apple транзакция, как она приехала.
///
/// Уезжает именно `jwsRepresentation`, а не разобранные поля: проверить
/// покупку может только тот, кто видел подпись, и телефон здесь почтальон, а
/// не свидетель. Поле называется так же, как в App Store Server API
/// (`signedTransaction`), чтобы имя на проводе совпадало с именем в
/// документации Apple, по которой сервер это проверяет.
struct PlusAttachRequest: Encodable {
    let signedTransaction: String
}

/// Ответ и `/plus/attach`, и `/plus/status` — одна форма на два маршрута
/// (спека §4). Сервер — источник правды для ЧУЖИХ глаз (профиль, лента);
/// гейты на этом телефоне считает StoreKit, поэтому ответ здесь ничего не
/// открывает и ничего не закрывает.
struct PlusStatusResponse: Decodable, Equatable {
    let active: Bool
    /// `nil` у неактивной подписки — «до какого числа» у неё нет.
    let until: Date?
    let productId: String?
    let isTrial: Bool

    init(active: Bool, until: Date?, productId: String?, isTrial: Bool) {
        self.active = active
        self.until = until
        self.productId = productId
        self.isTrial = isTrial
    }

    private enum CodingKeys: String, CodingKey {
        case active, until, productId, isTrial
    }

    /// Разбирается МЯГКО по той же причине, что каталог секретов: ответ
    /// приезжает в фоне и никого не ждёт, а старый сервер (Задача 1 ещё
    /// катится) поля `isTrial` может не прислать вовсе. Отсутствующее поле —
    /// «не сказано», а не повод уронить привязку покупки.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? false
        until = try c.decodeIfPresent(Date.self, forKey: .until)
        productId = try c.decodeIfPresent(String.self, forKey: .productId)
        isTrial = try c.decodeIfPresent(Bool.self, forKey: .isTrial) ?? false
    }
}

/// Два вызова «Плюса». Протокол, а не прямой `APIClient`, — чтобы правило
/// «одна транзакция уезжает ровно один раз, а сеть повторяется» проверялось
/// без сети (см. `PlusAttachTests`).
///
/// Не `@MainActor`: привязка покупки уходит соседней задачей с фоновым
/// приоритетом, и разбирать ответ там, где рисуется пейвол, незачем.
protocol PlusTransport: Sendable {
    func attach(signedTransaction: String) async throws -> PlusStatusResponse
    func status() async throws -> PlusStatusResponse
}

/// Настоящий транспорт поверх общего `APIClient` — конверт `{status, payload}`
/// тот разворачивает сам, как и у секретов.
struct PlusAPI: PlusTransport {
    /// Свой клиент — только для тестов с `MockURLProtocol`: `init` с ним
    /// `@MainActor`, потому что `APIClient` живёт там.
    private let injected: APIClient?

    init() { injected = nil }

    @MainActor
    init(client: APIClient) { injected = client }

    private func client() async -> APIClient {
        if let injected { return injected }
        return await MainActor.run { APIClient.shared }
    }

    func attach(signedTransaction: String) async throws -> PlusStatusResponse {
        try await client().post(
            APIEndpoint.plusAttach,
            body: PlusAttachRequest(signedTransaction: signedTransaction)
        )
    }

    /// Тело пустое, но POST, а не GET: маршрут читает аккаунт из JWT и на
    /// стороне сервера живёт рядом с `attach` (спека §4).
    func status() async throws -> PlusStatusResponse {
        struct Empty: Encodable {}
        return try await client().post(APIEndpoint.plusStatus, body: Empty())
    }
}
