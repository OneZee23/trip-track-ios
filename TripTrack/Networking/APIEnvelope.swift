import Foundation

enum APIStatus: String, Decodable { case ok, error }

struct APIEnvelope<T: Decodable>: Decodable {
    let status: APIStatus
    let payload: T?
    let code: String?
    let message: String?
    let serverVersion: Int?
    let serverLastModifiedAt: String?
}
