import SwiftUI

/// Picker-able profile background. Rendered 100% client-side from these
/// deterministic definitions — backend only stores the string identifier so
/// we can add / tune colors without a migration.
enum ProfileBackground: String, CaseIterable, Identifiable {
    case none      = ""
    case sunset    = "sunset"
    case ocean     = "ocean"
    case forest    = "forest"
    case mountain  = "mountain"
    case midnight  = "midnight"
    case dawn      = "dawn"
    case copper    = "copper"
    case slate     = "slate"
    case aurora    = "aurora"
    case sand      = "sand"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:     return "Default"
        case .sunset:   return "Sunset"
        case .ocean:    return "Ocean"
        case .forest:   return "Forest"
        case .mountain: return "Mountain"
        case .midnight: return "Midnight"
        case .dawn:     return "Dawn"
        case .copper:   return "Copper"
        case .slate:    return "Slate"
        case .aurora:   return "Aurora"
        case .sand:     return "Sand"
        }
    }

    /// Two-stop linear gradient definition. Start top-leading → bottom-trailing.
    var gradient: [Color] {
        switch self {
        case .none:
            return []
        case .sunset:
            return [Color(red: 0.98, green: 0.55, blue: 0.24),
                    Color(red: 0.95, green: 0.31, blue: 0.46),
                    Color(red: 0.56, green: 0.22, blue: 0.54)]
        case .ocean:
            return [Color(red: 0.25, green: 0.55, blue: 0.85),
                    Color(red: 0.14, green: 0.37, blue: 0.67),
                    Color(red: 0.08, green: 0.22, blue: 0.46)]
        case .forest:
            return [Color(red: 0.32, green: 0.59, blue: 0.36),
                    Color(red: 0.19, green: 0.42, blue: 0.28),
                    Color(red: 0.10, green: 0.25, blue: 0.18)]
        case .mountain:
            return [Color(red: 0.55, green: 0.62, blue: 0.70),
                    Color(red: 0.32, green: 0.42, blue: 0.52),
                    Color(red: 0.16, green: 0.22, blue: 0.30)]
        case .midnight:
            return [Color(red: 0.18, green: 0.15, blue: 0.38),
                    Color(red: 0.09, green: 0.08, blue: 0.22),
                    Color(red: 0.03, green: 0.02, blue: 0.08)]
        case .dawn:
            return [Color(red: 0.99, green: 0.85, blue: 0.62),
                    Color(red: 0.98, green: 0.65, blue: 0.48),
                    Color(red: 0.76, green: 0.42, blue: 0.47)]
        case .copper:
            return [Color(red: 0.72, green: 0.44, blue: 0.28),
                    Color(red: 0.48, green: 0.27, blue: 0.17),
                    Color(red: 0.26, green: 0.13, blue: 0.08)]
        case .slate:
            return [Color(red: 0.42, green: 0.47, blue: 0.52),
                    Color(red: 0.27, green: 0.31, blue: 0.36),
                    Color(red: 0.14, green: 0.16, blue: 0.20)]
        case .aurora:
            return [Color(red: 0.24, green: 0.85, blue: 0.66),
                    Color(red: 0.32, green: 0.44, blue: 0.82),
                    Color(red: 0.56, green: 0.28, blue: 0.74)]
        case .sand:
            return [Color(red: 0.95, green: 0.86, blue: 0.70),
                    Color(red: 0.84, green: 0.70, blue: 0.49),
                    Color(red: 0.55, green: 0.40, blue: 0.24)]
        }
    }

    @ViewBuilder
    func view() -> some View {
        let colors = gradient
        if colors.isEmpty {
            Color.clear
        } else {
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    static func from(_ raw: String?) -> ProfileBackground {
        guard let raw, !raw.isEmpty else { return .none }
        return ProfileBackground(rawValue: raw) ?? .none
    }
}

// MARK: - Banner helper

/// Rounded rectangle banner. Used at the top of own/public profile and as a
/// thin strip behind the avatar. Height is caller-controlled.
struct ProfileBackgroundBanner: View {
    let background: ProfileBackground
    var height: CGFloat = 140

    var body: some View {
        Group {
            if background == .none {
                Color.clear
            } else {
                background.view()
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 24,
                bottomTrailingRadius: 24,
                topTrailingRadius: 0
            )
        )
    }
}

// MARK: - Preview tile used in picker grids

struct ProfileBackgroundTile: View {
    let background: ProfileBackground
    let isSelected: Bool
    var size: CGFloat = 64

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(c.cardAlt)
            if background != .none {
                background.view()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                Image(systemName: "slash.circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(c.textTertiary)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? AppTheme.accent : Color.clear, lineWidth: 2.5)
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, AppTheme.accent)
                    .padding(4)
            }
        }
    }
}
