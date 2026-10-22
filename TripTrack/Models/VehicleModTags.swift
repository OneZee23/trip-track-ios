import Foundation

enum VehicleModTags {
    static func sanitized(_ input: [String]) -> [String] {
        var result: [String] = []
        for value in input {
            let tag = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
            if !tag.isEmpty, !result.contains(tag) { result.append(tag) }
            if result.count == 3 { break }
        }
        return result
    }

    static func effective(_ tags: [String], isPlus: Bool) -> [String] {
        isPlus ? sanitized(tags) : []
    }

    static func decodeJSON(_ json: String?) -> [String] {
        guard let data = json?.data(using: .utf8),
            let tags = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return tags
    }

    static func encodeJSON(_ tags: [String]) -> String? {
        guard let data = try? JSONEncoder().encode(sanitized(tags)) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
