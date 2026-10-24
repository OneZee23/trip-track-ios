import SwiftUI

struct GarageRegionChips: View {
    let regions: [MapRegionStat]
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = AppTheme.colors(for: scheme)
        ViewThatFits(in: .horizontal) {
            chips(c).font(.inter(10, weight: .medium))
            ScrollView(.horizontal, showsIndicators: false) { chips(c).font(.inter(10, weight: .medium)) }
        }
    }
    private func chips(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 6) {
            ForEach(regions.prefix(3)) { region in
                Text(region.localizedName(lang.language)).lineLimit(1).padding(.horizontal, 8).padding(.vertical, 5)
                    .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 7))
            }
            if regions.count > 3 { Text("+\(regions.count - 3)").padding(5) }
        }.foregroundStyle(c.textSecondary)
    }
}
