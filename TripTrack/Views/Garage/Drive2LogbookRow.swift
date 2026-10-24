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
                    // Their favicon, bundled once and shown only here, next to
                    // the link it names (owner, 23 Oct 2026; rules in
                    // docs/releases/0.9.1/drive2.md). Nothing is fetched.
                    Image("drive2_icon").resizable().interpolation(.high)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .opacity(parsed == nil ? 0.55 : 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            parsed == nil
                                ? AppStrings.garageDrive2Connect(lang.language)
                                : AppStrings.garageDrive2Title(lang.language)
                        )
                        .font(.inter(15, weight: parsed == nil ? .medium : .bold))
                        .foregroundStyle(parsed == nil ? c.textSecondary : c.text)
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
