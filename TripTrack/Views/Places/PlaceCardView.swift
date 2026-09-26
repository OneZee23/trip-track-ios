import SwiftUI

/// Строка места в списке (макет «Места» 0.8.1, S1).
///
/// Имя 16/500, под ним две серые строки: «118 проездов · последний 25 сент.»
/// и «обычно 18 мин от старта». Чип «частый гость» — НЕЙТРАЛЬНЫЙ, а не
/// акцентный, и «обычно…» тоже серая: терракота на этом экране достаётся
/// действию и одному крупному числу на экране места, а строка списка, где
/// акцентом горели и чип, и время, читалась тревогой, а не списком.
struct PlaceCardView: View {
    let item: PlaceListItem
    /// Компактная строка для длинного списка (S6): без «обычно…», одна
    /// строка подписи. У двадцати четырёх мест третья строка превращает
    /// список в простыню.
    var compact: Bool = false
    let onTap: () -> Void

    @EnvironmentObject private var lang: LanguageManager

    private static let dayMonth = LocalizedDateFormatter.templates("dMMM")

    var body: some View {
        let l = lang.language
        Button {
            Haptics.tap()
            onTap()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.place.name ?? AppStrings.placeUnnamed(l))
                            .font(AppType.itemTitle)
                            .foregroundStyle(AtlasTheme.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if let chip = chipText(l) { PlaceChipLabel(text: chip) }
                    }
                    Text(passesLine(l))
                        .font(AppType.meta)
                        .foregroundStyle(AtlasTheme.secondary)
                        .lineLimit(1)
                    if !compact, let usual = item.usual {
                        Text(AppStrings.placeUsually(l, time: CheckpointReading.clock(usual, lang: l)))
                            .font(AppType.meta)
                            .foregroundStyle(AtlasTheme.secondary)
                            .lineLimit(1)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AtlasTheme.secondary.opacity(0.7))
            }
            // 13 по горизонтали и 12 по вертикали — поля карточки «Ленты»
            // (`ProfileTripCardView`). Шестнадцать из HTML-макета делали
            // строку заметно просторнее соседних вкладок: «дизайн очень
            // такой приближенный» (владелец на устройстве 26 сентября).
            .padding(.leading, 13).padding(.trailing, 10)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("place_card_\(item.id.uuidString)")
    }

    private func chipText(_ l: LanguageManager.Language) -> String? {
        if item.isFrequentGuest { return AppStrings.placeChipFrequent(l) }
        if item.isFirstTime { return AppStrings.placeChipFirst(l) }
        return nil
    }

    /// «118 проездов · последний 25 сент.»; без проездов — просто число.
    private func passesLine(_ l: LanguageManager.Language) -> String {
        let n = item.stats.passCount
        let count = "\(AppStrings.formattedCount(n, lang: l)) \(AppStrings.nounPasses(l, n))"
        guard let last = item.lastAt, let f = Self.dayMonth[l] else { return count }
        return "\(count) · \(AppStrings.placeLastPass(l, date: f.string(from: last)))"
    }
}

/// Нейтральный чип «частый гость» / «первый раз здесь».
///
/// Строчными и серым — это ПОДПИСЬ, а не награда (правило 0.6.8: опыта и
/// значков места не дают). Прописными акцентом он читался медалью.
struct PlaceChipLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AppType.caption)
            .foregroundStyle(AtlasTheme.secondary)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(AtlasTheme.chip, in: Capsule())
            .fixedSize()
    }
}
