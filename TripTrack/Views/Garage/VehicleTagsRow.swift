import SwiftUI

struct VehicleTagsRow: View {
    let tags: [String]
    let showsPaidCosmetics: Bool

    var body: some View {
        let visible = VehicleModTags.effective(tags, isPlus: showsPaidCosmetics)
        if !visible.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { chips(visible) }
                VStack(spacing: 6) { chips(visible) }
            }
        }
    }

    @ViewBuilder
    private func chips(_ tags: [String]) -> some View {
        ForEach(tags, id: \.self) { tag in
            Text(tag).font(.inter(11, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .padding(.vertical, 4).padding(.horizontal, 8)
                .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        ProBadge(height: 14)
    }
}
