import SwiftUI

/// Rows for the small anchored popovers behind our «…» buttons.
///
/// Why a popover and not a `Menu`: a Menu is a UIKit context menu, and closing
/// one animates a snapshot of the source button back down over ~0.9s on top of
/// a rounded-SQUARE plate with its own shadow. On a round button over a warm
/// background that plate reads as a translucent square frame blinking around
/// the button, and it cannot be reshaped from SwiftUI (`contentShape` and
/// `contentShape(.contextMenuPreview,)` were both measured frame-by-frame off a
/// screen recording — neither touches it). A popover has no source snapshot at
/// all, and unlike an action sheet it stays anchored to the button it came from.
///
/// Host it with `.popover(isPresented:) { ActionPopoverList(items: …) }` — the
/// list applies `presentationCompactAdaptation(.popover)` itself so iPhone
/// keeps the anchored popover instead of adapting to a full sheet.
struct ActionPopoverList: View {
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let systemImage: String
        var isDestructive: Bool = false
        let action: () -> Void
    }

    let items: [Item]
    var width: CGFloat = 232

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button {
                    Haptics.tap()
                    item.action()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 20)
                        Text(item.title)
                            .font(.system(size: 15, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(item.isDestructive ? AppTheme.red : c.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < items.count - 1 {
                    Divider()
                        .overlay(c.border)
                        .padding(.leading, 48)
                }
            }
        }
        .frame(width: width)
        .presentationCompactAdaptation(.popover)
    }
}
