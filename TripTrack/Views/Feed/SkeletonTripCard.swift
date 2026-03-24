import SwiftUI

struct SkeletonTripCard: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(alignment: .leading, spacing: 12) {
            // Header: vehicle badge + date
            HStack(spacing: 10) {
                Circle()
                    .fill(c.cardAlt)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(c.cardAlt)
                        .frame(width: 80, height: 12)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(c.cardAlt)
                        .frame(width: 140, height: 10)
                }
                Spacer()
            }

            // Title
            RoundedRectangle(cornerRadius: 4)
                .fill(c.cardAlt)
                .frame(width: 160, height: 16)

            // Map placeholder
            RoundedRectangle(cornerRadius: 10)
                .fill(c.cardAlt)
                .frame(height: 80)

            // Stats row
            HStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(c.cardAlt)
                            .frame(width: 48, height: 20)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(c.cardAlt)
                            .frame(width: 56, height: 10)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .surfaceCard(cornerRadius: 16)
        .shimmer()
    }
}
