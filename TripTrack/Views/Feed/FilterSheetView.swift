import SwiftUI

struct FilterSheetView: View {
    @Binding var filters: TripFilters
    let regions: [String]
    let onApply: () -> Void
    let onResetSecondary: () -> Void
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(alignment: .leading, spacing: 0) {
            Text(AppStrings.filters(lang.language))
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(c.text)
                .padding(.bottom, 20)

            // Region chips
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text(AppStrings.region(lang.language))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
            }
            .padding(.bottom, 10)

            FlowLayout(spacing: 8) {
                // "All" chip
                Button {
                    filters.region = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.system(size: 12))
                        Text(AppStrings.all(lang.language))
                    }
                    .glassPill(isActive: filters.region == nil)
                }
                .buttonStyle(.plain)

                ForEach(regions, id: \.self) { region in
                    Button {
                        filters.region = region
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin")
                                .font(.system(size: 11))
                            Text(region)
                        }
                        .glassPill(isActive: filters.region == region)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Buttons
            HStack(spacing: 10) {
                Button {
                    onResetSecondary()
                } label: {
                    Text(AppStrings.reset(lang.language))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(c.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button {
                    onApply()
                } label: {
                    Text(AppStrings.apply(lang.language))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .padding(.bottom, 20)
        .background(c.card)
    }
}

// MARK: - Flow Layout (for region chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
