import Foundation

/// The registration plate as free text.
///
/// Research (14.07 — EasyPark, ParkMobile, DVLA) says every serious product
/// takes the plate as plain text. No masks, no country detection: the shortcut
/// people reach for — "four digits means a Russian motorcycle" — collides with
/// German, US and Indian formats the moment anyone crosses a border, and a mask
/// that guesses wrong is worse than no mask at all.
///
/// So this type does one job: keep out what cannot be part of a plate anywhere.
enum VehiclePlate {
    /// Upper bound on length. Long enough for the longest real formats
    /// (including separators), short enough that the chip never wraps.
    static let maxLength = 13

    /// Letters of any alphabet, digits, and the three separators plates
    /// actually use. Everything else — emoji above all — is dropped.
    ///
    /// Similar-looking letters (Cyrillic А and Latin A, В and B …) are left
    /// exactly as typed. Transliterating them would silently rewrite a Russian
    /// plate into a Latin one, and the two are different strings to everyone
    /// who later reads them.
    static func sanitize(_ raw: String) -> String {
        var out = ""
        out.reserveCapacity(min(raw.count, maxLength))
        for ch in raw {
            guard ch.isLetter || ch.isNumber || ch == " " || ch == "-" || ch == "." else { continue }
            out.append(ch)
            if out.count == maxLength { break }
        }
        return out
    }

    /// What gets stored: sanitized, with the edges trimmed. Empty means
    /// "no plate", which is a perfectly ordinary state — the field is optional.
    static func normalized(_ raw: String) -> String {
        sanitize(raw).trimmingCharacters(in: .whitespaces)
    }
}
