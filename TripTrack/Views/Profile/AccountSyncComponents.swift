import SwiftUI

// MARK: - Section Label (12pt account variant)

/// Uppercased tracking label above the account-page cards («СИНХРОНИЗАЦИЯ»,
/// «ПРИВАТНОСТЬ», «АККАУНТ»). Deliberately NOT reusing the 10pt
/// `GarageSectionLabel` — the account section's Figma spec is explicitly
/// 12pt bold / tracking 0.36. Vertical rhythm (14–18pt above / 8pt below)
/// is handled by callers.
struct AccountSectionLabel: View {
    let text: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .tracking(0.36)
            .foregroundStyle(c.textTertiary)
    }
}

// MARK: - Settings Row

/// Figma settings row: px14 py13, 17pt icon in a fixed 22pt slot (keeps
/// titles aligned across rows with different glyph widths), 15-medium title,
/// wrapping 11.5-regular subtitle, arbitrary trailing content (Toggle /
/// value+chevron / none), optional 1px bottom divider inset to the text
/// column.
struct AccountSettingsRow<Trailing: View>: View {
    let icon: String
    var iconColor: Color?
    let title: String
    var titleColor: Color?
    var subtitle: String?
    var showsDivider: Bool = false
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(iconColor ?? c.textSecondary)
                    .frame(width: 22, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(titleColor ?? c.text)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(c.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                trailing()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)

            if showsDivider {
                Rectangle()
                    .fill(c.border)
                    .frame(height: 1)
                    .padding(.leading, 48) // 14 (px) + 22 (icon slot) + 12 (gap)
            }
        }
    }
}

// MARK: - Formatting

enum AccountFormat {
    /// «a•••@icloud.com» — first character of the local part + bullet mask +
    /// full domain (Figma F11). Pure and total: degenerate inputs (empty,
    /// no `@`, `@`-first, single-char local part) return safely instead of
    /// crashing or leaking the full address.
    static func maskedEmail(_ email: String) -> String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "" }
        guard let atIndex = trimmed.firstIndex(of: "@") else {
            // Not an email shape — still never echo the raw string back.
            return "\(first)•••"
        }
        let domain = trimmed[trimmed.index(after: atIndex)...]
        guard atIndex != trimmed.startIndex else {
            // "@domain" — no local part to take a first character from.
            return "•••@\(domain)"
        }
        return "\(first)•••@\(domain)"
    }
}
