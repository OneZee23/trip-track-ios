import SwiftUI

struct Drive2LogbookRow: View {
    let link: String?
    var onConnect: (() -> Void)? = nil
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        let parsed = Drive2Link(link ?? "")
        let c = AppTheme.colors(for: scheme)
        if parsed != nil || onConnect != nil {
            Button {
                Haptics.tap()
                if let parsed { openURL(parsed.url) } else { onConnect?() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.up.right").font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(parsed == nil ? c.textSecondary : AppTheme.accent)
                        .frame(width: 36, height: 36)
                        .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            parsed == nil
                                ? AppStrings.garageDrive2Connect(lang.language)
                                : AppStrings.garageDrive2Title(lang.language)
                        )
                        .font(.inter(15, weight: parsed == nil ? .medium : .bold))
                        .foregroundStyle(parsed == nil ? c.textSecondary : c.text)
                        if let parsed {
                            Text(parsed.url.absoluteString.replacingOccurrences(of: "https://www.", with: ""))
                                .font(.inter(12)).foregroundStyle(c.textSecondary).lineLimit(1).truncationMode(.tail)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(
                        c.textTertiary)
                }
                .padding(14).surfaceCard(cornerRadius: 16)
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityIdentifier("garage_drive2_row")
        }
    }
}
