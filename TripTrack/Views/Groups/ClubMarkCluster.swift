import SwiftUI

/// The club marks arranged as a group, used as the hero on the clubs screen.
///
/// It replaced a generic pixel car in a ring — an image that said «vehicle»
/// on a screen whose subject is «communities». Overlapping marks read as a
/// group of somebodies, which is what a club is, and they use the artwork the
/// screen is already promising two scrolls further down.
struct ClubMarkCluster: View {
    var size: CGFloat = 66
    var overlap: CGFloat = 0.30

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        HStack(spacing: -size * overlap) {
            ForEach(Array(Club.all.prefix(4))) { club in
                ZStack {
                    Circle()
                        .fill(club.tint)
                    Circle()
                        .strokeBorder(c.card, lineWidth: 3)
                    if let asset = club.asset {
                        Image(asset)
                            .resizable()
                            // After `resizable()`, as everywhere else.
                            .interpolation(.none)
                            .scaledToFit()
                            .padding(size * 0.18)
                    } else {
                        Text(club.emoji).font(.system(size: size * 0.42))
                    }
                }
                .frame(width: size, height: size)
            }
        }
        // One image, not four buttons.
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(true)
    }
}
