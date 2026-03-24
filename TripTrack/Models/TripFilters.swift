import Foundation

struct TripFilters {
    var region: String?
    var dateFrom: Date?    // range start (inclusive)
    var dateTo: Date?      // range end (inclusive)

    var isActive: Bool {
        region != nil || dateFrom != nil || dateTo != nil
    }

    var hasDateFilter: Bool {
        dateFrom != nil || dateTo != nil
    }

    static let empty = TripFilters()
}
