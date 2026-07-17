import SwiftUI

/// Dark-glass 3-item pill over the night map (Figma «segment3»): container
/// white@10% + 1px white@16% border + blur, items 13pt Bold, active = solid
/// accent capsule with white text.
struct MapSegmentControl: View {
    @Binding var mode: MyMapMode
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MyMapMode.allCases, id: \.self) { item in
                let active = item == mode
                Button {
                    withAnimation(.snappy(duration: 0.2)) { mode = item }
                    Haptics.selection()
                } label: {
                    Text(item.title(lang.language))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(active ? .white : .white.opacity(0.6))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background {
                            if active {
                                Capsule().fill(AppTheme.accent)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("map_mode_\(item.rawValue)")
            }
        }
        .padding(3)
        .background {
            Capsule().fill(.white.opacity(0.10))
            Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
        .background(.ultraThinMaterial, in: Capsule())
    }
}
