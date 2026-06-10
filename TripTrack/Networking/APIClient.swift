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

    init(session: URLSession = .shared, tokenStore: TokenStore = .shared) {
        // iOS picks HTTP/3 automatically via Alt-Svc header from server
        // (Cloudflare advertises `alt-svc: h3=":443"`). On flaky RU networks
        // QUIC sometimes survives where HTTP/2 over TCP gets reset because
        // the operator's DPI box doesn't fingerprint UDP/QUIC handshakes
        // as aggressively. Use shared session — earlier custom-session
        // experiments (waitsForConnectivity + long timeouts) made
        // everything fail with -1005, so we stay conservative.
        self.session = session
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
        // Host whitelist for SSRF defense. `getBytes` only ever fetches
        // photos from R2 presigned URLs (issued by our own backend). If the
        // backend were ever compromised or a man-in-the-middle injected a
        // malicious URL into a `/sync/pull` payload, an unrestricted fetch
        // could be used to probe internal services on the user's network
        // (`http://router.local/admin`) or sniff via tracking pixels.
        // Allow only HTTPS to known R2/Cloudflare hosts.
        guard url.scheme == "https",
              let host = url.host?.lowercased(),
              Self.isAllowedPhotoHost(host) else {
            throw APIError.transport("disallowed photo host: \(url.host ?? "?")")
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.invalidHTTPStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }

    /// Allowlist of hosts that legit photo URLs can come from. Adjust here
    /// if the storage backend changes (e.g. moving to R2 custom domain).
    private static func isAllowedPhotoHost(_ host: String) -> Bool {
        host.hasSuffix(".r2.cloudflarestorage.com") ||
        host.hasSuffix(".r2.dev") ||
        host == "trip-track.app" ||
        host.hasSuffix(".trip-track.app")
    }

    // MARK: - Core request path

    private func performPost<Req: Encodable, Res: Decodable>(path: String, body: Req, requiresAuth: Bool, isRetry: Bool, singleAttempt: Bool = false) async throws -> Res {
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
        let rawSize = rawJsonData.count
        // Tiered per-request ceiling. Reads (tiny request bodies — feed,
        // profile, reactions) get 30s so a stalled cold connection on a RU
        // network errors fast and the auto-retry path below has time to
        // recover within a single user "load" wait. Uploads (large bodies)
        // keep the original 90s headroom — shaving them aborts perfectly
        // healthy slow-mobile POSTs mid-stream.
        req.timeoutInterval = rawSize >= 4_096 ? 90 : 30

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
        // Multi-attempt retry for transient TLS/connection failures. -1005
        // (NSURLErrorNetworkConnectionLost) hits when a pooled HTTP/2 stream
        // got reset by server-side keepalive; -1001 (timedOut) hits on cold
        // RU connections where TLS handshake to Cloudflare exceeds the
        // per-request ceiling before the response lands. Both heal on a
        // fresh ephemeral session — usually first retry, but in production
        // we observed two consecutive -1005s on /auth/login with a single
        // retry, leaving the user permanently locked out at the sign-in
        // screen. Three total attempts (1 + 2 retries) with progressive
        // backoff lets a flaky RU network recover within a single user
        // wait without making large-body uploads waste bandwidth on repeat
        // sends — those keep the original 1-retry budget.
        // singleAttempt is set by the refresh path so the auth-token rotation
        // call doesn't burn 90+ seconds on its own retries while everyone
        // else is awaiting the refreshTask. Large bodies get 2 attempts (one
        // retry's worth of bandwidth is enough for 100KB+ uploads); small
        // bodies get 3 attempts (cheap to retry, helpful on flaky RU TLS).
        let maxAttempts = singleAttempt ? 1 : (isLargeBody ? 2 : 3)
        let (data, response) = try await retrying(
            maxAttempts: maxAttempts, label: "POST \(path)"
        ) { attemptSession in
            try await self.sendOnce(req: req, body: jsonData, isLargeBody: isLargeBody, session: attemptSession)
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
            // Post-refresh USER_NOT_AUTH means our freshly-rotated access
            // token is itself invalid (server-side JWT secret rotation,
            // race with a concurrent revoke). No more refresh attempts —
            // sign out so SIWA can re-establish a clean session.
            if code == "USER_NOT_AUTH", requiresAuth, isRetry {
                apiAuthLog.error("POST \(path, privacy: .public) USER_NOT_AUTH after refresh — forcing signout")
                AuthService.shared.forceSignOut()
            }
            // UNKNOWN_SERVER_ERROR is the catch-all when the backend's
            // JsonRpcExceptionFilter sees a non-AppError exception (DB
            // connection blip, unhandled crash mid-handler, transient
            // pool exhaustion). These usually heal on a single retry —
            // retrying once at this layer means the upper-layer
            // SyncQueue stops parking ops to `failedQueue` for one-off
            // server hiccups, and the user sees a clean banner.
            if code == "UNKNOWN_SERVER_ERROR", !isRetry {
                apiAuthLog.notice("POST \(path, privacy: .public) UNKNOWN_SERVER_ERROR — retrying once after 1s")
                try? await Task.sleep(for: .seconds(1))
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
            // Mirrors performPost: post-refresh USER_NOT_AUTH = dead session.
            if code == "USER_NOT_AUTH", requiresAuth, isRetry {
                apiAuthLog.error("GET \(path, privacy: .public) USER_NOT_AUTH after refresh — forcing signout")
                AuthService.shared.forceSignOut()
            }
            // See performPost: retry-once on transient server errors.
            if code == "UNKNOWN_SERVER_ERROR", !isRetry {
                apiAuthLog.notice("GET \(path, privacy: .public) UNKNOWN_SERVER_ERROR — retrying once after 1s")
                try? await Task.sleep(for: .seconds(1))
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
        let (data, response) = try await retrying(
            maxAttempts: 3, label: "MULTIPART \(path)"
        ) { attemptSession in
            try await attemptSession.data(for: req)
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
            // Mirrors performPost: post-refresh USER_NOT_AUTH = dead session.
            if code == "USER_NOT_AUTH", isRetry {
                apiAuthLog.error("MULTIPART \(path, privacy: .public) USER_NOT_AUTH after refresh — forcing signout")
                AuthService.shared.forceSignOut()
            }
            // See performPost: retry-once on transient server errors.
            if code == "UNKNOWN_SERVER_ERROR", !isRetry {
                apiAuthLog.notice("MULTIPART \(path, privacy: .public) UNKNOWN_SERVER_ERROR — retrying once after 1s")
                try? await Task.sleep(for: .seconds(1))
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

    /// Multi-attempt wrapper. -1005 (NSURLErrorNetworkConnectionLost) and
    /// -1001 (timedOut) are the dominant transient failures on RU mobile
    /// networks via Cloudflare; both heal on a fresh ephemeral session.
    /// First attempt uses the shared session (warm pool); subsequent
    /// attempts spin a fresh ephemeral session with a brief backoff. Other
    /// URLError codes (.cancelled, .dataNotAllowed) bail immediately.
    private func retrying(
        maxAttempts: Int,
        label: String,
        perform: (URLSession) async throws -> (Data, URLResponse)
    ) async throws -> (Data, URLResponse) {
        var lastError: URLError?
        for attempt in 0..<maxAttempts {
            let attemptSession: URLSession
            if attempt == 0 {
                attemptSession = session
            } else {
                let freshConfig = URLSessionConfiguration.ephemeral
                freshConfig.timeoutIntervalForRequest = 90
                attemptSession = URLSession(configuration: freshConfig)
                // Backoff 0.8s, 1.2s before attempts 2 and 3 — formula
                // `attempt * 0.4 + 0.4`. Small enough not to compound, big
                // enough to let TLS state settle between cold reconnects.
                try? await Task.sleep(nanoseconds: UInt64((Double(attempt) * 0.4 + 0.4) * 1_000_000_000))
            }
            defer { if attempt > 0 { attemptSession.invalidateAndCancel() } }
            do {
                return try await perform(attemptSession)
            } catch let e as URLError where e.code == .networkConnectionLost || e.code == .timedOut {
                apiAuthLog.notice("\(label, privacy: .public) attempt \(attempt + 1)/\(maxAttempts) \(e.code.rawValue)")
                lastError = e
                continue
            } catch let e as URLError {
                apiAuthLog.error("\(label, privacy: .public) non-retryable \(e.code.rawValue) \(e.localizedDescription, privacy: .public)")
                throw APIError.network(e)
            }
        }
        apiAuthLog.error("\(label, privacy: .public) all \(maxAttempts) attempts failed code=\(lastError?.code.rawValue ?? -1)")
        throw APIError.network(lastError ?? URLError(.networkConnectionLost))
    }

    /// Single HTTP roundtrip. Picks `upload(for:from:)` for large bodies and
    /// `data(for:)` for small ones — the upload variant tolerates ~80KB JSON
    /// POSTs that would hang via data(for:) on flakey connections.
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
            // Each POST is singleAttempt so it can't loop 3×30s and stall every
            // other in-flight authed call awaiting refreshTask.
            func postRefresh() async throws -> RefreshResponse {
                try await self.performPost(
                    path: APIEndpoint.refresh, body: RefreshRequest(refreshToken: refresh),
                    requiresAuth: false, isRetry: true, singleAttempt: true)
            }
            do {
                let res: RefreshResponse
                do {
                    res = try await postRefresh()
                } catch APIError.network(let lostErr) where lostErr.code == .networkConnectionLost {
                    // A lost rotation response leaves us holding the *old*
                    // refresh token. The backend honours it within a short
                    // rotation grace window (idempotent: the same old token
                    // re-derives the same successor), so one prompt re-attempt
                    // recovers the session instead of bricking it.
                    //
                    // Scoped to .networkConnectionLost ONLY — a fast-failing
                    // pooled-stream reset, the typical "response dropped" case.
                    // We deliberately do NOT re-attempt on .timedOut: that
                    // already burned the full ~30s timeout, and since refresh is
                    // single-flight (every other authed call awaits refreshTask),
                    // a second 30s attempt would stall the whole app ~60s. A
                    // timeout instead falls through to "keep session" below and
                    // lets the NEXT authed call refresh again — still within the
                    // 60s backend grace window for any normal user action.
                    apiAuthLog.notice("refresh: connection lost — one fast re-attempt within grace window")
                    try? await Task.sleep(for: .seconds(1))
                    res = try await postRefresh()
                }
                self.tokenStore.set(accessToken: res.accessToken, refreshToken: res.refreshToken)
                apiAuthLog.notice("refresh: succeeded, new tokens stored")
            } catch APIError.network(let urlErr) {
                // Transient network failure — keep session. The next user
                // action will trigger another refresh; the refresh token in
                // keychain is still valid as far as we know.
                apiAuthLog.notice("refresh: network failure code=\(urlErr.code.rawValue) — keeping session")
                throw APIError.network(urlErr)
            } catch let error as APIError {
                // Whitelist of transient APIError cases that should NOT sign
                // the user out. Everything else (including unknown server
                // codes the backend may add later) → forceSignOut. Inverting
                // the default this way prevents zombie sessions from new
                // server error codes that no one updated this switch for.
                let isTransient: Bool
                switch error {
                case .network, .decoding, .transport:
                    isTransient = true
                case .invalidHTTPStatus(let code):
                    // 5xx = server hiccup (retry later); 4xx = our auth is
                    // bad (sign out). Without this split a hypothetical 401
                    // response without the typed envelope would be treated
                    // as transient and leave a dead session forever.
                    isTransient = code >= 500
                default:
                    isTransient = false
                }
                if isTransient {
                    apiAuthLog.notice("refresh: transient (\(String(describing: error), privacy: .public)) — keeping session")
                } else {
                    apiAuthLog.error("refresh: rejected (\(String(describing: error), privacy: .public)) — forcing signout")
                    AuthService.shared.forceSignOut()
                }
                throw error
            } catch {
                apiAuthLog.notice("refresh: unknown error (\(String(describing: error), privacy: .public)) — keeping session")
                throw error
            }
        }
        refreshTask = task
        try await task.value
    }
}
