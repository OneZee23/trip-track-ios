import Foundation
import OSLog

final class APILogger {
    private let logger = Logger(subsystem: "com.triptrack", category: "api")

    func log(request: URLRequest, bodyPreview: String?) {
        guard AppConfig.isDebug else { return }
        let method = request.httpMethod ?? "?"
        let path = request.url?.path ?? "?"
        logger.debug("→ \(method) \(path) body=\(bodyPreview ?? "-", privacy: .public)")
    }

    func log(response: URLResponse, data: Data, duration: TimeInterval) {
        guard AppConfig.isDebug else { return }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let preview = redact(String(data: data.prefix(2048), encoding: .utf8) ?? "")
        logger.debug("← [\(status)] (\(Int(duration * 1000))ms) \(preview, privacy: .public)")
    }

    private func redact(_ s: String) -> String {
        s.replacingOccurrences(of: #""refreshToken"\s*:\s*"[^"]+""#, with: "\"refreshToken\":\"***\"", options: .regularExpression)
         .replacingOccurrences(of: #""accessToken"\s*:\s*"[^"]+""#, with: "\"accessToken\":\"***\"", options: .regularExpression)
         .replacingOccurrences(of: #""identityToken"\s*:\s*"[^"]+""#, with: "\"identityToken\":\"***\"", options: .regularExpression)
    }
}
