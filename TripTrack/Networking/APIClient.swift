import Foundation
import OSLog

private let apiAuthLog = Logger(subsystem: "com.triptrack", category: "api-auth")

@MainActor
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let tokenStore: TokenStore
    private let logger = APILogger()
    private var refreshTask: Task<Void, Error>?

    init(session: URLSession? = nil, tokenStore: TokenStore = .shared) {
        // Custom URLSession instead of `.shared` so we control connectivity
        // semantics. URLSession.shared has 60s "between packets" timeout that
        // never actually fires for stalled uploads on flaky networks (observed
        // /trips/upsert hanging indefinitely on Russian ISPs DPI-throttling
        // direct-to-DigitalOcean traffic). `waitsForConnectivity` makes the
        // session retry transparently when the network drops out instead of
        // failing immediately, and the longer timeoutIntervalForResource gives
        // big trip uploads with many trackPoints actual time to finish over
        // unstable connections.
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.waitsForConnectivity = true
            config.timeoutIntervalForRequest = 180
            config.timeoutIntervalForResource = 600
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            self.session = URLSession(configuration: config)
        }
        self.tokenStore = tokenStore
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()

        // Codable strategies use the dedicated `ISODate` helpers below, which
        // wrap explicit `DateFormatter`s pinned to UTC + `en_US_POSIX`. We
        // moved off `ISO8601DateFormatter` because under iOS 18 concurrency
        // it intermittently parsed `Z`-suffixed timestamps as if they were
        // device-local time, surfacing as a "3 hours ago" reaction in MSK.
        decoder.dateDecodingStrategy = .custom { d in
            let c = try d.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = ISODate.parse(s) { return date }
            throw APIError.decoding("invalid ISO8601: \(s)")
        }
        encoder.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(ISODate.format(date))
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
        let hasToken = tokenStore.accessToken != nil
        if requiresAuth, let token = tokenStore.accessToken {
            req.setValue(token, forHTTPHeaderField: "x-access-token")
        }
        if requiresAuth {
            apiAuthLog.notice("POST \(path, privacy: .public) hasToken=\(hasToken) isRetry=\(isRetry)")
        }
        let rawJsonData = try encoder.encode(body)
        // Per-request 90s ceiling. URLSession's default 60s
        // timeoutIntervalForRequest is "between packets" and observed in prod
        // to never fire for stalled large uploads on RU networks. Hard cap.
        req.timeoutInterval = 90
        let rawSize = rawJsonData.count

        // Gzip bodies >4KB. Russian ISPs DPI-throttle TLS streams >16KB to
        // foreign DC IPs (DigitalOcean, Cloudflare) — large uploads stall
        // permanently with NSURLErrorNetworkConnectionLost cascade. Trip JSON
        // with hundreds of trackPoints compresses ~80% (repetitive floats),
        // bringing 50KB payloads under the 16KB DPI threshold. Backend nginx
        // has `gunzip on;` to transparently decompress before reaching Express.
        let jsonData: Data
        let bodySize: Int
        if rawSize >= 4_096, let gz = rawJsonData.gzipped() {
            jsonData = gz
            bodySize = gz.count
            req.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
            apiAuthLog.notice("POST \(path, privacy: .public) gzipped \(rawSize)→\(gz.count) bytes")
        } else {
            jsonData = rawJsonData
            bodySize = rawSize
        }
        let isLargeBody = bodySize >= 10_000
        if isLargeBody {
            apiAuthLog.notice("POST \(path, privacy: .public) bodySize=\(bodySize) bytes (large, upload task)")
        }
        // Log the original (un-gzipped) JSON for human readability — gzipped
        // bytes would just be opaque binary in the diagnostic log.
        logger.log(request: req, bodyPreview: String(data: rawJsonData, encoding: .utf8))

        let start = Date()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await sendOnce(req: req, body: jsonData, isLargeBody: isLargeBody, session: session)
        } catch let e as URLError where e.code == .networkConnectionLost {
            // -1005 (NSURLErrorNetworkConnectionLost) is the classic URLSession
            // failure mode when a pooled HTTP/1.1 connection was already closed
            // by the server-side keepalive timer but URLSession tried to write
            // to it anyway. Apple-recommended remedy: catch and retry once on a
            // fresh ephemeral session — that connection is guaranteed not to
            // come from the broken pool entry. Without this the SyncQueue
            // looped forever on /trips/upsert because every retry hit the same
            // dead pool slot. One-shot retry only; if it fails again, give up
            // and let SyncQueue's normal failedQueue path take over.
            apiAuthLog.notice("POST \(path, privacy: .public) -1005 networkConnectionLost — retrying on fresh ephemeral session")
            let freshConfig = URLSessionConfiguration.ephemeral
            freshConfig.timeoutIntervalForRequest = 90
            let freshSession = URLSession(configuration: freshConfig)
            defer { freshSession.invalidateAndCancel() }
            do {
                (data, response) = try await sendOnce(req: req, body: jsonData, isLargeBody: isLargeBody, session: freshSession)
            } catch let e2 as URLError {
                apiAuthLog.error("POST \(path, privacy: .public) retry also failed: \(e2.localizedDescription, privacy: .public) code=\(e2.code.rawValue)")
                throw APIError.network(e2)
            }
        } catch let e as URLError {
            apiAuthLog.error("POST \(path, privacy: .public) failed after \(Int(Date().timeIntervalSince(start) * 1000))ms: \(e.localizedDescription, privacy: .public) code=\(e.code.rawValue)")
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
            postBanIfNeeded(code)
            let lastModified = envelope.serverLastModifiedAt.flatMap { ISODate.parse($0) }
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
            postBanIfNeeded(code)
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
            postBanIfNeeded(code)
            throw APIError.from(code: code, message: envelope.message ?? "", serverVersion: envelope.serverVersion, serverLastModifiedAt: nil)
        }
    }

    /// Fan-out ban detection to any observer (notably `AuthService`, which
    /// triggers `signOut()`). Invoked at every error-path response — same
    /// hook regardless of whether the request was POST, GET, or multipart.
    private func postBanIfNeeded(_ code: String) {
        guard code == "USER_BANNED" else { return }
        NotificationCenter.default.post(name: .userBanned, object: nil)
    }

    // MARK: - HTTP transport helper

    /// Single HTTP roundtrip. Picks `upload(for:from:)` for large bodies and
    /// `data(for:)` for small ones — the upload variant tolerates ~80KB JSON
    /// POSTs that would hang via data(for:) on flakey connections. The
    /// network-connection-lost retry in the callers wraps this whole call.
    private func sendOnce(
        req: URLRequest, body: Data?, isLargeBody: Bool, session: URLSession,
    ) async throws -> (Data, URLResponse) {
        if let body, isLargeBody {
            return try await session.upload(for: req, from: body)
        }
        var req = req
        if let body { req.httpBody = body }
        return try await session.data(for: req)
    }

    // MARK: - Token refresh (single-flight)

    private func refreshIfNeeded() async throws {
        if let existing = refreshTask {
            apiAuthLog.notice("refresh: awaiting in-flight task")
            try await existing.value
            return
        }
        let task = Task<Void, Error> { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.refreshTask = nil } }
            guard let refresh = self.tokenStore.refreshToken else {
                apiAuthLog.error("refresh: no refresh token in keychain — forcing signout")
                AuthService.shared.forceSignOut()
                throw APIError.invalidRefreshToken
            }
            apiAuthLog.notice("refresh: posting /auth/refresh")
            do {
                let res: RefreshResponse = try await self.performPost(
                    path: APIEndpoint.refresh, body: RefreshRequest(refreshToken: refresh),
                    requiresAuth: false, isRetry: true)  // isRetry=true prevents infinite loop
                self.tokenStore.set(accessToken: res.accessToken, refreshToken: res.refreshToken)
                apiAuthLog.notice("refresh: succeeded, new tokens stored")
            } catch {
                // Refresh failed permanently — backend rejected our refresh
                // token (expired 7d, row deleted, secret rotated). Without a
                // forceSignOut here the app would be stuck: isSignedIn=true,
                // every authed call returns USER_NOT_AUTH, no recovery path.
                // Tearing down the session lets the user re-authenticate via
                // Sign in with Apple instead of a permanent silent failure.
                apiAuthLog.error("refresh: failed (\(String(describing: error), privacy: .public)) — forcing signout")
                AuthService.shared.forceSignOut()
                throw error
            }
        }
        refreshTask = task
        try await task.value
    }
}
