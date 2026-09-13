import SwiftUI

/// Карточка места в списке (S1): имя, «11 проездов · последний 6 сен»,
/// акцентная «обычно 2:14 от старта», чип «Частый гость» / «Первый раз здесь».
struct PlaceCardView: View {
    let item: PlaceListItem
    let onTap: () -> Void

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager

    private static let dayMonth = LocalizedDateFormatter.templates("dMMM")

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        Button {
            Haptics.tap()
            onTap()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.place.name ?? AppStrings.placeUnnamed(l))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text(passesLine(l))
                        .font(.system(size: 12))
                        .foregroundStyle(c.textSecondary)
                        .lineLimit(1)
                    if let usual = item.usual {
                        Text(AppStrings.placeUsually(l, time: CheckpointReading.clock(usual, lang: l)))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                            .lineLimit(1)
                    }
                    if item.isFrequentGuest || item.isFirstTime {
                        Text(item.isFrequentGuest ? AppStrings.placeChipFrequent(l) : AppStrings.placeChipFirst(l))
                            .font(.system(size: 10, weight: .heavy))
                            .textCase(.uppercase)
                            .tracking(0.4)
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(AppTheme.accentBg, in: Capsule())
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .surfaceCard(cornerRadius: 16)
        .accessibilityIdentifier("place_card_\(item.id.uuidString)")
    }

    /// «11 проездов · последний 6 сен»; без проездов — просто число.
    private func passesLine(_ l: LanguageManager.Language) -> String {
        let n = item.stats.passCount
        let count = "\(AppStrings.formattedCount(n, lang: l)) \(AppStrings.nounPasses(l, n))"
        guard let last = item.lastAt, let f = Self.dayMonth[l] else { return count }
        return "\(count) · \(AppStrings.placeLastPass(l, date: f.string(from: last)))"
    }
}
