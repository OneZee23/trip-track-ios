import SwiftUI

/// The shape of the content that is coming, drawn in grey while it loads.
///
/// A list that is fetching should look like a list. Showing a picture in its
/// place means the layout is built twice — once as an illustration, then again
/// as rows — and the jump is the part that feels slow, more than the wait
/// itself. A skeleton also answers the question the spinner does not: how much
/// is about to appear, and in what shape.
///
/// The illustrations stay where there is genuinely nothing to imitate: an empty
/// result, a failure, a screen with no content at all. Those need explaining,
/// and a drawn scene explains better than a grey rectangle.
struct SkeletonPlaceholder: View {
    enum Shape {
        /// Avatar plus two lines — people, notifications, reactions.
        case row
        /// A feed card: header, map block, footer.
        case card
    }

    var shape: Shape = .row
    var count: Int = 4

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmering = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(spacing: shape == .card ? 14 : 12) {
            ForEach(0..<count, id: \.self) { _ in
                switch shape {
                case .row:  rowSkeleton(c)
                case .card: cardSkeleton(c)
                }
            }
        }
        .opacity(shimmering ? 1.0 : 0.55)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
            value: shimmering
        )
        .onAppear { shimmering = true }
        // One announcement for the whole block; a screen reader has nothing to
        // gain from a dozen unlabelled grey rectangles.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppStrings.loadingGeneric(lang.language))
    }

    private func bar(_ c: AppTheme.Colors, width: CGFloat?, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(c.cardAlt)
            .frame(width: width, height: height)
    }

    private func rowSkeleton(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(c.cardAlt)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 7) {
                bar(c, width: 150, height: 11)
                bar(c, width: 96, height: 9)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private func cardSkeleton(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle().fill(c.cardAlt).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 6) {
                    bar(c, width: 120, height: 10)
                    bar(c, width: 72, height: 8)
                }
                Spacer(minLength: 0)
            }
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(c.cardAlt)
                .frame(height: 140)
            HStack(spacing: 16) {
                bar(c, width: 54, height: 9)
                bar(c, width: 54, height: 9)
                bar(c, width: 54, height: 9)
                Spacer(minLength: 0)
            }
        }
        .padding(13)
        .surfaceCard(cornerRadius: 16)
    }
}
