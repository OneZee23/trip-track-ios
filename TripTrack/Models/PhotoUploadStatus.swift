import Foundation

/// Upload status for photos in sync pipeline.
enum PhotoUploadStatus: Int16 {
    case localOnly = 0
    case uploading = 1
    case uploaded = 2
    case failed = 3
}
