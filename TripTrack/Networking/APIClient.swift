import Foundation

@MainActor
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let tokenStore: TokenStore
    private let logger = APILogger()
    private var refreshTask: Task<Void, Error>?

    init(session: URLSession = .shared, tokenStore: TokenStore = .shared) {
        self.session = session
        self.tokenStore = tokenStore
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()

        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        decoder.dateDecodingStrategy = .custom { d in
            let c = try d.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = withFrac.date(from: s) { return date }
            if let date = plain.date(from: s) { return date }
            throw APIError.decoding("invalid ISO8601: \(s)")
        }
        encoder.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(withFrac.string(from: date))
        }
    }

    func post<Req: Encodable, Res: Decodable>(_ path: String, body: Req, requiresAuth: Bool = true) async throws -> Res {
        try await performPost(path: path, body: body, requiresAuth: requiresAuth, isRetry: false)
    }

    func get<Res: Decodable>(_ path: String, requiresAuth: Bool = true) async throws -> Res {
        try await performGet(path: path, requiresAuth: requiresAuth, isRetry: false)
    }

    func uploadMultipart<Res: Decodable>(
        _ path: String,
        fields: [(name: String, value: String)],
        file: (name: String, filename: String, mimeType: String, data: Data)
    ) async throws -> Res {
        try await performMultipart(path: path, fields: fields, file: file, isRetry: false)
    }

    func getBytes(url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.invalidHTTPStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }

    // MARK: - Core request path

    private func performPost<Req: Encodable, Res: Decodable>(path: String, body: Req, requiresAuth: Bool, isRetry: Bool) async throws -> Res {
        let url = AppConfig.apiBaseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if requiresAuth, let token = tokenStore.accessToken {
            req.setValue(token, forHTTPHeaderField: "x-access-token")
        }
        let jsonData = try encoder.encode(body)
        req.httpBody = jsonData
        logger.log(request: req, bodyPreview: String(data: jsonData, encoding: .utf8))

        let start = Date()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch let e as URLError {
            throw APIError.network(e)
        }
        logger.log(response: response, data: data, duration: Date().timeIntervalSince(start))

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.invalidHTTPStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let envelope: APIEnvelope<Res>
        do {
            envelope = try decoder.decode(APIEnvelope<Res>.self, from: data)
        } catch {
            throw APIError.decoding("\(error)")
        }

        switch envelope.status {
        case .ok:
            guard let payload = envelope.payload else {
                if let empty = EmptyResponse() as? Res { return empty }
                throw APIError.decoding("missing payload for ok status")
            }
            return payload
        case .error:
            let code = envelope.code ?? "UNKNOWN"
            let message = envelope.message ?? ""
            if code == "USER_NOT_AUTH", requiresAuth, !isRetry {
                try await refreshIfNeeded()
                return try await performPost(path: path, body: body, requiresAuth: requiresAuth, isRetry: true)
            }
            if code == "USER_BANNED" {
                Task { @MainActor in
                    NotificationCenter.default.post(name: .userBanned, object: nil)
                }
            }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let lastModified = envelope.serverLastModifiedAt.flatMap { s -> Date? in
                iso.date(from: s) ?? ISO8601DateFormatter().date(from: s)
            }
            throw APIError.from(code: code, message: message, serverVersion: envelope.serverVersion, serverLastModifiedAt: lastModified)
        }
    }

    private func performGet<Res: Decodable>(path: String, requiresAuth: Bool, isRetry: Bool) async throws -> Res {
        let url = AppConfig.apiBaseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if requiresAuth, let token = tokenStore.accessToken {
            req.setValue(token, forHTTPHeaderField: "x-access-token")
        }
        logger.log(request: req, bodyPreview: nil)

        let start = Date()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch let e as URLError {
            throw APIError.network(e)
        }
        logger.log(response: response, data: data, duration: Date().timeIntervalSince(start))

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.invalidHTTPStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let envelope: APIEnvelope<Res>
        do {
            envelope = try decoder.decode(APIEnvelope<Res>.self, from: data)
        } catch {
            throw APIError.decoding("\(error)")
        }

        switch envelope.status {
        case .ok:
            guard let payload = envelope.payload else {
                if let empty = EmptyResponse() as? Res { return empty }
                throw APIError.decoding("missing payload for ok status")
            }
            return payload
        case .error:
            let code = envelope.code ?? "UNKNOWN"
            if code == "USER_NOT_AUTH", requiresAuth, !isRetry {
                try await refreshIfNeeded()
                return try await performGet(path: path, requiresAuth: requiresAuth, isRetry: true)
            }
            if code == "USER_BANNED" {
                Task { @MainActor in
                    NotificationCenter.default.post(name: .userBanned, object: nil)
                }
            }
            throw APIError.from(code: code, message: envelope.message ?? "", serverVersion: envelope.serverVersion, serverLastModifiedAt: nil)
        }
    }

    private func performMultipart<Res: Decodable>(
        path: String, fields: [(name: String, value: String)],
        file: (name: String, filename: String, mimeType: String, data: Data),
        isRetry: Bool
    ) async throws -> Res {
        let url = AppConfig.apiBaseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if let token = tokenStore.accessToken {
            req.setValue(token, forHTTPHeaderField: "x-access-token")
        }

        var builder = MultipartFormDataBuilder()
        for f in fields { builder.append(field: f.name, value: f.value) }
        builder.append(fileField: file.name, filename: file.filename, mimeType: file.mimeType, data: file.data)
        builder.finalize()

        req.setValue(builder.contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = builder.body
        logger.log(request: req, bodyPreview: "<multipart \(builder.body.count) bytes>")

        let start = Date()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch let e as URLError {
            throw APIError.network(e)
        }
        logger.log(response: response, data: data, duration: Date().timeIntervalSince(start))

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.invalidHTTPStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let envelope = try decoder.decode(APIEnvelope<Res>.self, from: data)
        switch envelope.status {
        case .ok:
            guard let payload = envelope.payload else {
                if let empty = EmptyResponse() as? Res { return empty }
                throw APIError.decoding("missing payload")
            }
            return payload
        case .error:
            let code = envelope.code ?? "UNKNOWN"
            if code == "USER_NOT_AUTH", !isRetry {
                try await refreshIfNeeded()
                return try await performMultipart(path: path, fields: fields, file: file, isRetry: true)
            }
            if code == "USER_BANNED" {
                Task { @MainActor in
                    NotificationCenter.default.post(name: .userBanned, object: nil)
                }
            }
            throw APIError.from(code: code, message: envelope.message ?? "", serverVersion: envelope.serverVersion, serverLastModifiedAt: nil)
        }
    }

    // MARK: - Token refresh (single-flight)

    private func refreshIfNeeded() async throws {
        if let existing = refreshTask {
            try await existing.value
            return
        }
        let task = Task<Void, Error> { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.refreshTask = nil } }
            guard let refresh = self.tokenStore.refreshToken else {
                throw APIError.invalidRefreshToken
            }
            let res: RefreshResponse = try await self.performPost(
                path: APIEndpoint.refresh, body: RefreshRequest(refreshToken: refresh),
                requiresAuth: false, isRetry: true)  // isRetry=true prevents infinite loop
            self.tokenStore.set(accessToken: res.accessToken, refreshToken: res.refreshToken)
        }
        refreshTask = task
        try await task.value
    }
}
